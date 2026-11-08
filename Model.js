.pragma library

// Data model for the Time Switch bar widget: parsing and bounding API
// responses, and formatting durations. Pure functions so tests/ can run them
// in Node.

var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
var LOGO_URL = /^\/logos\/([A-Za-z0-9][A-Za-z0-9._-]{0,119})$/
var HEX_COLOR = /^#[0-9a-f]{6}$/i
var MAX_COMPANIES = 50
var MAX_NAME = 80

function isUuid(value) {
  return typeof value === "string" && UUID.test(value)
}

// Milliseconds since the epoch, or NaN for anything that is not an ISO date
// inside a sane window (1970 to 2200).
function parseTime(value) {
  if (typeof value !== "string" || value.length > 40) return NaN
  var ms = Date.parse(value)
  if (!isFinite(ms) || ms < 0 || ms > 7258118400000) return NaN
  return ms
}

function cleanName(value) {
  var text = typeof value === "string" ? value : ""
  // Control characters out, whitespace collapsed, length bounded.
  text = text.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim()
  return text.length > MAX_NAME ? text.slice(0, MAX_NAME - 1) + "…" : text
}

function parseCompany(raw) {
  if (!raw || typeof raw !== "object" || !isUuid(raw.id)) return null
  var logo = typeof raw.logoUrl === "string" ? LOGO_URL.exec(raw.logoUrl) : null
  return {
    id: raw.id.toLowerCase(),
    name: cleanName(raw.name),
    color: typeof raw.color === "string" && HEX_COLOR.test(raw.color) ? raw.color.toLowerCase() : "",
    logoKey: logo ? logo[1] : "",
    archived: raw.archived === true
  }
}

// Active companies from GET /api/v1/companies, alphabetical as the API
// returns them, at most MAX_COMPANIES.
function parseCompanies(data) {
  if (!(data instanceof Array)) return null
  var out = []
  for (var i = 0; i < data.length && out.length < MAX_COMPANIES; i++) {
    var company = parseCompany(data[i])
    if (company && !company.archived) out.push(company)
  }
  return out
}

// GET /api/v1/status → { active: { id, companyId, startedAt, company } | null,
// serverTime }. Returns null when the shape is wrong.
function parseStatus(data) {
  if (!data || typeof data !== "object") return null
  var serverTime = parseTime(data.serverTime)
  if (!isFinite(serverTime)) return null
  var raw = data.activeSession
  if (raw === null || raw === undefined) return { active: null, serverTime: serverTime }
  if (typeof raw !== "object" || !isUuid(raw.id) || !isUuid(raw.companyId)) return null
  var startedAt = parseTime(raw.startedAt)
  if (!isFinite(startedAt)) return null
  return {
    active: {
      id: raw.id.toLowerCase(),
      companyId: raw.companyId.toLowerCase(),
      startedAt: startedAt,
      company: parseCompany(raw.company)
    },
    serverTime: serverTime
  }
}

function seconds(value) {
  var n = Number(value)
  return isFinite(n) && n >= 0 && n < 1e9 ? n : 0
}

// GET /api/v1/summary → total seconds across every company in the range.
function parseSummaryTotal(data) {
  if (!data || typeof data !== "object" || !(data.companies instanceof Array)) return null
  var total = 0
  for (var i = 0; i < data.companies.length && i < MAX_COMPANIES * 2; i++)
    total += seconds(data.companies[i] && data.companies[i].totalSeconds)
  return total
}

// GET /api/v1/companies/:id/period → { totalSeconds, start }.
function parsePeriod(data) {
  if (!data || typeof data !== "object") return null
  return { totalSeconds: seconds(data.totalSeconds), start: parseTime(data.start) }
}

// GET /api/v1/sessions?limit=… → end of the most recent finished session,
// or NaN.
function lastEndedAt(data) {
  if (!(data instanceof Array)) return NaN
  var latest = NaN
  for (var i = 0; i < data.length && i < 500; i++) {
    var ended = parseTime(data[i] && data[i].endedAt)
    if (isFinite(ended) && !(ended <= latest)) latest = ended
  }
  return latest
}

// Local midnight today, and local midnight on the most recent Monday.
function dayStart(nowMs) {
  var d = new Date(nowMs)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

function weekStart(nowMs) {
  var d = new Date(dayStart(nowMs))
  var sinceMonday = (d.getDay() + 6) % 7
  d.setDate(d.getDate() - sinceMonday)
  return d.getTime()
}

// A total fetched at fetchedAt keeps growing while a session runs.
function liveSeconds(baseSeconds, fetchedAt, nowMs, running) {
  var base = seconds(baseSeconds)
  if (!running || !isFinite(fetchedAt)) return base
  return base + Math.max(0, nowMs - fetchedAt) / 1000
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// 10038 → "2:47:18"
function formatClock(totalSeconds) {
  var s = Math.max(0, Math.floor(seconds(totalSeconds)))
  return Math.floor(s / 3600) + ":" + pad2(Math.floor(s / 60) % 60) + ":" + pad2(s % 60)
}

// 10038 → "2:47"
function formatShort(totalSeconds) {
  var s = Math.max(0, Math.floor(seconds(totalSeconds)))
  return Math.floor(s / 3600) + ":" + pad2(Math.floor(s / 60) % 60)
}

// The bar pill: minutes and seconds for the first hour so it visibly ticks
// (47 → "0:47", 754 → "12:34"), then hours and minutes (10038 → "2:47").
function formatPill(totalSeconds) {
  var s = Math.max(0, Math.floor(seconds(totalSeconds)))
  if (s < 3600) return Math.floor(s / 60) + ":" + pad2(s % 60)
  return formatShort(s)
}

// 226584 → "62.94" (hours, two decimals, like the dashboard)
function formatHours(totalSeconds) {
  return (Math.floor(seconds(totalSeconds) / 36) / 100).toFixed(2)
}

// First letter of a name for a logo-less mark.
function initial(name) {
  var text = cleanName(name)
  return text === "" ? "?" : text.charAt(0).toUpperCase()
}

// Normalises the server setting to an https origin, or "".
function normalizeServer(value) {
  var text = typeof value === "string" ? value.trim() : ""
  if (text === "") return ""
  if (!/^https?:\/\//i.test(text)) text = "https://" + text
  var m = /^(https:\/\/[A-Za-z0-9.-]+(?::\d{1,5})?)\/*$/i.exec(text)
  return m ? m[1].toLowerCase() : ""
}

// Access service-token credentials as Cloudflare issues them.
function validClientId(value) {
  return typeof value === "string" && /^[0-9a-f]{32}\.access$/i.test(value.trim())
}

function validClientSecret(value) {
  return typeof value === "string" && /^[A-Za-z0-9._~+/=-]{20,200}$/.test(value.trim())
}
