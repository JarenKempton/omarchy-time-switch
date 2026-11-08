#!/usr/bin/env node
// node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("./load-model")

const CO = "3f2a9c1e-5b7d-4e8a-9c6f-2d1b0a9e8f7c"
const SESSION = "0b6c3f1e-2d4a-4c5b-9e6f-7a8b9c0d1e2f"

// Arrays from the vm context are a different realm; compare as plain JSON.
const plain = (v) => JSON.parse(JSON.stringify(v))

test("formats durations like the dashboard", () => {
  assert.equal(M.formatClock(10038), "2:47:18")
  assert.equal(M.formatShort(10038), "2:47")
  assert.equal(M.formatClock(0), "0:00:00")
  assert.equal(M.formatHours(226584), "62.94")
  assert.equal(M.formatHours(18720), "5.20")
  assert.equal(M.formatShort(-5), "0:00")
  assert.equal(M.formatShort("nonsense"), "0:00")
})

test("ticks in seconds for the first hour, then hours and minutes", () => {
  assert.equal(M.formatPill(0), "0:00")
  assert.equal(M.formatPill(7), "0:07")
  assert.equal(M.formatPill(754), "12:34")
  assert.equal(M.formatPill(3599), "59:59")
  assert.equal(M.formatPill(3600), "1:00")
  assert.equal(M.formatPill(10038), "2:47")
})

test("parses status with and without a running session", () => {
  const idle = M.parseStatus({ activeSession: null, serverTime: "2026-11-08T01:00:00.000Z" })
  assert.equal(idle.active, null)
  assert.equal(idle.serverTime, Date.parse("2026-11-08T01:00:00.000Z"))

  const busy = M.parseStatus({
    serverTime: "2026-11-08T01:00:00.000Z",
    activeSession: {
      id: SESSION,
      companyId: CO,
      startedAt: "2026-11-07T22:12:42.000Z",
      company: { id: CO, name: "Northstar", color: "#62E6A7", logoUrl: "/logos/northstar-1a2b3c4d.svg" },
    },
  })
  assert.equal(busy.active.companyId, CO)
  assert.equal(busy.active.company.color, "#62e6a7")
  assert.equal(busy.active.company.logoKey, "northstar-1a2b3c4d.svg")
})

test("rejects malformed status", () => {
  assert.equal(M.parseStatus(null), null)
  assert.equal(M.parseStatus({ activeSession: null }), null)
  assert.equal(M.parseStatus({ serverTime: "x", activeSession: null }), null)
  assert.equal(
    M.parseStatus({ serverTime: "2026-11-08T01:00:00Z", activeSession: { id: "1", companyId: CO, startedAt: "2026-11-08T00:00:00Z" } }),
    null,
  )
})

test("keeps only active, well-formed companies", () => {
  const list = M.parseCompanies([
    { id: CO, name: "Northstar", color: "#62e6a7", logoUrl: "/logos/northstar-1a2b3c4d.svg", archived: false },
    { id: "1c41b5d5-a753-4a83-a7c7-00d32a1b6845", name: "Old", archived: true },
    { id: "not-a-uuid", name: "Bad" },
    null,
  ])
  assert.deepEqual(plain(list).map((c) => c.name), ["Northstar"])
  assert.equal(M.parseCompanies({}), null)
})

test("neutralises hostile company fields", () => {
  const [c] = M.parseCompanies([
    {
      id: CO,
      name: '<img src="https://example.invalid/t">\u0000\n' + "x".repeat(500),
      color: "red; background:url(x)",
      logoUrl: "https://example.invalid/logo.svg",
    },
  ])
  assert.ok(c.name.length <= 80)
  assert.ok(!/[\u0000-\u001f]/.test(c.name))
  assert.equal(c.color, "")
  assert.equal(c.logoKey, "")
  assert.equal(M.parseCompany({ id: CO, logoUrl: "/logos/../secret" }).logoKey, "")
  assert.equal(M.parseCompany({ id: CO, logoUrl: "/logos/a/b.svg" }).logoKey, "")
})

test("sums summary totals and reads periods", () => {
  assert.equal(M.parseSummaryTotal({ companies: [{ totalSeconds: 100 }, { totalSeconds: 50.5 }, { totalSeconds: -9 }] }), 150.5)
  assert.equal(M.parseSummaryTotal({}), null)
  const period = M.parsePeriod({ totalSeconds: 226584, start: "2026-10-12T21:28:00.000Z" })
  assert.equal(period.totalSeconds, 226584)
  assert.equal(M.parsePeriod({ totalSeconds: 1e12 }).totalSeconds, 0)
})

test("finds the most recent finished session", () => {
  const t = M.lastEndedAt([
    { endedAt: null },
    { endedAt: "2026-11-07T23:04:00.000Z" },
    { endedAt: "2026-11-06T23:04:00.000Z" },
  ])
  assert.equal(t, Date.parse("2026-11-07T23:04:00.000Z"))
  assert.ok(isNaN(M.lastEndedAt([])))
})

test("computes local day and Monday week starts", () => {
  const sat = new Date(2026, 10, 7, 18, 21).getTime()
  assert.equal(M.dayStart(sat), new Date(2026, 10, 7).getTime())
  assert.equal(M.weekStart(sat), new Date(2026, 10, 2).getTime())
  const mon = new Date(2026, 10, 2, 0, 5).getTime()
  assert.equal(M.weekStart(mon), new Date(2026, 10, 2).getTime())
  const sun = new Date(2026, 10, 8, 23, 0).getTime()
  assert.equal(M.weekStart(sun), new Date(2026, 10, 2).getTime())
})

test("grows totals only while running", () => {
  assert.equal(M.liveSeconds(100, 1000, 6000, true), 105)
  assert.equal(M.liveSeconds(100, 1000, 6000, false), 100)
  assert.equal(M.liveSeconds(100, 9000, 6000, true), 100)
})

test("validates server and credentials", () => {
  assert.equal(M.normalizeServer("time.example.dev/"), "https://time.example.dev")
  assert.equal(M.normalizeServer("https://Time.Example.dev"), "https://time.example.dev")
  assert.equal(M.normalizeServer("http://time.example.dev"), "")
  assert.equal(M.normalizeServer("https://x.dev/path"), "")
  assert.equal(M.normalizeServer("https://x.dev\"; rm -rf ~"), "")
  assert.ok(M.validClientId("0123456789abcdef0123456789abcdef.access"))
  assert.ok(!M.validClientId("01234567.access"))
  assert.ok(M.validClientSecret("Example-Secret_0123456789abcdefghijklmnopqrstuvwxyz"))
  assert.ok(!M.validClientSecret("short"))
  assert.ok(!M.validClientSecret("has space in it but is long enough"))
})

test("gives a plain initial for logo-less marks", () => {
  assert.equal(M.initial("northstar"), "N")
  assert.equal(M.initial("  "), "?")
  assert.equal(M.initial("<b>x</b>"), "<")
})
