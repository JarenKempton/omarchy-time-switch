import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Talks to a Time Switch server through a Cloudflare Access service token.
//
// Credentials live in $XDG_CONFIG_HOME/omarchy/time-switch/ (server,
// client-id, client-secret), mode 600, and are only ever sent as request
// headers to that server. Nothing here runs downloaded content: responses are
// parsed as JSON, bounded and validated in Model.js, and logos are rendered
// from SVG text as image data.
Item {
  id: root
  visible: false

  property var settings: ({})
  // Poll faster while the panel is open.
  property bool panelOpen: false

  readonly property string configDir: {
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    return (xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.config") + "/omarchy/time-switch"
  }

  // ---- configuration -------------------------------------------------------
  property string fileServer: ""
  property string clientId: ""
  property string clientSecret: ""
  readonly property string server: {
    var fromSettings = Model.normalizeServer(String(settings && settings.server ? settings.server : ""))
    return fromSettings !== "" ? fromSettings : Model.normalizeServer(fileServer)
  }
  readonly property bool configured: server !== "" && Model.validClientId(clientId) && Model.validClientSecret(clientSecret)

  FileView {
    id: serverFile
    path: root.configDir + "/server"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.fileServer = text().trim()
    onLoadFailed: root.fileServer = ""
  }
  FileView {
    id: idFile
    path: root.configDir + "/client-id"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.clientId = text().trim()
    onLoadFailed: root.clientId = ""
  }
  FileView {
    id: secretFile
    path: root.configDir + "/client-secret"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.clientSecret = text().trim()
    onLoadFailed: root.clientSecret = ""
  }

  // ---- state ---------------------------------------------------------------
  // "setup" | "loading" | "ready" | "offline" | "denied" (Access rejected the
  // token) | "forbidden" (the Worker does not grant this token the API)
  property string phase: configured ? "loading" : "setup"
  property string lastError: ""
  property var session: null         // { id, companyId, startedAt, company }
  property var companies: []         // [{ id, name, color, logoKey }]
  property real clockOffset: 0       // server time minus local time, ms
  property real fetchedAt: NaN       // local ms when totals were fetched
  property real todayBase: 0
  property real weekBase: 0
  property var periods: ({})         // companyId -> totalSeconds
  property real lastEnded: NaN
  property var logos: ({})           // logoKey -> data: URL
  property bool busy: false
  property real now: Date.now()

  readonly property bool tracking: session !== null
  readonly property real elapsed: tracking ? Math.max(0, (now + clockOffset - session.startedAt) / 1000) : 0
  readonly property real todaySeconds: Model.liveSeconds(todayBase, fetchedAt, now, tracking)
  readonly property real weekSeconds: Model.liveSeconds(weekBase, fetchedAt, now, tracking)
  readonly property var activeCompany: tracking ? (companyById(session.companyId) || session.company) : null

  function companyById(id) {
    for (var i = 0; i < companies.length; i++) if (companies[i].id === id) return companies[i]
    return null
  }
  function periodSeconds(companyId) {
    var base = periods[companyId]
    if (base === undefined) return NaN
    return Model.liveSeconds(base, fetchedAt, now, tracking && session.companyId === companyId)
  }
  function logoFor(company) {
    return company && company.logoKey ? (logos[company.logoKey] || "") : ""
  }

  onConfiguredChanged: {
    phase = configured ? "loading" : "setup"
    if (configured) Qt.callLater(refresh)
    restartLive()
  }
  onServerChanged: { logos = ({}); if (configured) Qt.callLater(refresh); restartLive() }
  onClientIdChanged: restartLive()
  onClientSecretChanged: restartLive()

  Timer {
    interval: 1000
    repeat: true
    running: root.tracking || root.panelOpen
    onTriggered: root.now = Date.now()
  }
  Timer {
    id: pollTimer
    // With the live stream up, polling is only a safety net.
    interval: root.liveConnected ? 120000 : root.panelOpen ? 5000 : Math.max(10, Number(root.settings && root.settings.pollSeconds) || 15) * 1000
    repeat: true
    running: root.configured
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  onPanelOpenChanged: if (panelOpen && configured) refresh()

  // ---- live updates --------------------------------------------------------
  // The server pushes a message over a WebSocket (/api/v1/live) whenever a
  // session or device changes. QML's WebSocket can't send the Access headers,
  // so curl holds the socket; each message only triggers a refresh, its
  // content is never parsed. The headers reach curl through a here-document,
  // so the secret never appears in a process's arguments. If curl is missing
  // or the socket drops, it reconnects with backoff and polling carries on.
  // TCP keepalives notice a socket that died during suspend, and each
  // connection is capped at 15 minutes, so a curl orphaned by a crashed
  // shell exits on its own.
  property bool liveConnected: false
  property int liveRetryMs: 1000
  property real liveStartedAt: 0

  function restartLive() {
    liveRetry.stop()
    if (live.running) live.running = false   // onExited reconnects
    else if (configured) liveRetry.restart()
  }

  Process {
    id: live
    command: ["sh", "-c",
      'd="$2"; exec curl -sS -N --fail --keepalive-time 15 --max-time 900 -o - -H @/dev/fd/3 "$1/api/v1/live" 3<<EOF\n' +
      'CF-Access-Client-Id: $(cat "$d/client-id")\n' +
      'CF-Access-Client-Secret: $(cat "$d/client-secret")\n' +
      'EOF\n',
      "time-switch-live", root.server.replace(/^https:/, "wss:"), root.configDir]
    stdout: SplitParser {
      // Messages arrive back to back with no separator; any data will do.
      splitMarker: ""
      onRead: {
        root.liveConnected = true
        liveDebounce.restart()
      }
    }
    onStarted: root.liveStartedAt = Date.now()
    onExited: {
      root.liveConnected = false
      // A connection that lasted a while just idled out: reconnect at once.
      // Quick failures back off up to a minute.
      if (Date.now() - root.liveStartedAt > 30000) root.liveRetryMs = 1000
      else root.liveRetryMs = Math.min(60000, root.liveRetryMs * 2)
      if (root.configured) liveRetry.restart()
    }
  }
  Timer {
    id: liveRetry
    interval: root.liveRetryMs
    onTriggered: if (root.configured && !live.running) live.running = true
  }
  Timer {
    id: liveDebounce
    interval: 250
    onTriggered: root.refresh()
  }

  // ---- HTTP ----------------------------------------------------------------
  readonly property int maxBytes: 512 * 1024
  readonly property int timeoutMs: 10000
  property var pending: []

  function request(method, path, body, done, raw) {
    if (!configured) return
    var xhr = new XMLHttpRequest()
    var entry = { xhr: xhr, started: Date.now(), aborted: false }
    pending.push(entry)
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var i = pending.indexOf(entry)
      if (i >= 0) pending.splice(i, 1)
      if (entry.aborted) { done("offline", null); return }
      if (xhr.status === 0) { done("offline", null); return }
      var text = xhr.responseText || ""
      if (text.length > maxBytes) { done("too large", null); return }
      if (xhr.status === 401 || xhr.status === 403) {
        // The Worker answers 403 with a JSON error when Access let the token
        // through but the Worker does not grant it this route; Access itself
        // rejects with a login page.
        var code = ""
        try { code = String((JSON.parse(text).error || {}).code || "") } catch (e) {}
        done(code.indexOf("service_token_") === 0 ? "forbidden" : "denied", null)
        return
      }
      if (xhr.status < 200 || xhr.status >= 300) { done("HTTP " + xhr.status, null); return }
      if (raw) { done("", text); return }
      // Access answers a rejected token with its login page, not JSON.
      var data = null
      try { data = JSON.parse(text) } catch (e) { done("denied", null); return }
      done("", data && typeof data === "object" && "data" in data ? data.data : null)
    }
    xhr.open(method, server + path)
    xhr.setRequestHeader("CF-Access-Client-Id", clientId)
    xhr.setRequestHeader("CF-Access-Client-Secret", clientSecret)
    if (!raw) xhr.setRequestHeader("Accept", "application/json")
    if (body !== null) xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(body === null ? null : JSON.stringify(body))
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.pending.length > 0
    onTriggered: {
      var cutoff = Date.now() - root.timeoutMs
      root.pending.slice().forEach(function(entry) {
        if (entry.started < cutoff) { entry.aborted = true; entry.xhr.abort() }
      })
    }
  }

  function fail(error) {
    if (error === "") return false
    lastError = error
    phase = error === "denied" ? "denied" : error === "forbidden" ? "forbidden" : "offline"
    return true
  }

  // One round: status first (it decides what else is worth asking), then
  // companies, totals, periods and the last finished session in parallel.
  property bool refreshing: false
  property bool refreshQueued: false
  onRefreshingChanged: if (!refreshing && refreshQueued) { refreshQueued = false; Qt.callLater(refresh) }
  function refresh() {
    if (!configured) return
    // A change pushed mid-refresh must not be lost: run once more after.
    if (refreshing) { refreshQueued = true; return }
    refreshing = true
    request("GET", "/api/v1/status", null, function(error, data) {
      if (fail(error)) { refreshing = false; return }
      var status = Model.parseStatus(data)
      if (!status) { refreshing = false; fail("bad response"); return }
      var t = Date.now()
      clockOffset = status.serverTime - t
      root.session = status.active
      now = t
      loadDetails(t)
    })
  }

  function loadDetails(t) {
    var left = 5
    var next = { today: todayBase, week: weekBase, periods: {}, lastEnded: lastEnded }
    function finish() {
      if (--left > 0) return
      todayBase = next.today
      weekBase = next.week
      periods = next.periods
      lastEnded = next.lastEnded
      fetchedAt = t
      refreshing = false
      if (phase === "ready") lastError = ""
    }
    var serverNow = t + clockOffset
    var end = new Date(serverNow + 60000).toISOString()

    request("GET", "/api/v1/companies", null, function(error, data) {
      var list = error ? null : Model.parseCompanies(data)
      if (list) {
        companies = list
        fetchPeriods(list, next, function() { finish() })
        fetchLogos(list)
      } else {
        fail(error || "bad response")
        finish()
      }
    })
    request("GET", "/api/v1/summary?from=" + encodeURIComponent(new Date(Model.dayStart(t)).toISOString()) + "&to=" + encodeURIComponent(end), null, function(error, data) {
      var total = error ? null : Model.parseSummaryTotal(data)
      if (total !== null) next.today = total
      finish()
    })
    request("GET", "/api/v1/summary?from=" + encodeURIComponent(new Date(Model.weekStart(t)).toISOString()) + "&to=" + encodeURIComponent(end), null, function(error, data) {
      var total = error ? null : Model.parseSummaryTotal(data)
      if (total !== null) next.week = total
      finish()
    })
    request("GET", "/api/v1/sessions?limit=5", null, function(error, data) {
      if (!error) next.lastEnded = Model.lastEndedAt(data)
      finish()
    })
    // Counts as ready once status has answered; details fill in behind it.
    phase = "ready"
    finish()
  }

  function fetchPeriods(list, next, done) {
    if (list.length === 0) { done(); return }
    var left = list.length
    list.forEach(function(company) {
      request("GET", "/api/v1/companies/" + company.id + "/period", null, function(error, data) {
        var period = error ? null : Model.parsePeriod(data)
        if (period) next.periods[company.id] = period.totalSeconds
        if (--left === 0) done()
      })
    })
  }

  function fetchLogos(list) {
    list.forEach(function(company) {
      var key = company.logoKey
      if (!key || logos[key] !== undefined) return
      var marked = Object.assign({}, logos)
      marked[key] = ""
      logos = marked
      request("GET", "/logos/" + key, null, function(error, text) {
        if (error || typeof text !== "string" || text.length > 256 * 1024) return
        var svg = text.trim()
        if (!/^(<\?xml[^>]*>\s*)?<svg[\s>]/i.test(svg)) return
        var updated = Object.assign({}, logos)
        updated[key] = "data:image/svg+xml;utf8," + encodeURIComponent(svg)
        logos = updated
      }, true)
    })
  }

  // ---- actions -------------------------------------------------------------
  function start(companyId) {
    if (!configured || busy || !Model.isUuid(companyId)) return
    busy = true
    request("POST", "/api/v1/sessions", { companyId: companyId, startedAt: new Date(Date.now() + clockOffset).toISOString() }, function(error, data) {
      busy = false
      // Show the new session at once rather than after the next poll, so a
      // second press can't act on the old state.
      var started = error ? null : Model.parseStatus({ activeSession: data, serverTime: new Date(Date.now() + clockOffset).toISOString() })
      if (started && started.active) { session = started.active; now = Date.now() }
      if (error) lastError = error === "forbidden" || error === "denied" ? "This token can't start sessions." : "Couldn't start: " + error
      refreshing = false
      refresh()
    })
  }

  function stop() {
    if (!configured || busy || !tracking) return
    busy = true
    request("POST", "/api/v1/sessions/" + session.id + "/stop", { endedAt: new Date(Date.now() + clockOffset).toISOString() }, function(error) {
      busy = false
      if (!error) session = null
      if (error) lastError = error === "forbidden" || error === "denied" ? "This token can't stop sessions." : "Couldn't stop: " + error
      refreshing = false
      refresh()
    })
  }

  // ---- setup ---------------------------------------------------------------
  // Writes server, client ID and secret over stdin (never argv) into files
  // only this user can read.
  signal saved(bool ok)
  function saveCredentials(serverText, id, secret) {
    var origin = Model.normalizeServer(serverText)
    if (origin === "" || !Model.validClientId(id) || !Model.validClientSecret(secret)) { saved(false); return }
    writer.payload = origin + "\n" + id.trim() + "\n" + secret.trim() + "\n"
    writer.running = true
  }
  Process {
    id: writer
    property string payload: ""
    stdinEnabled: true
    command: ["sh", "-c",
      'umask 077; d="$1"; mkdir -p "$d" && chmod 700 "$d" || exit 1; ' +
      'IFS= read -r s && IFS= read -r i && IFS= read -r k || exit 1; ' +
      'printf %s "$s" > "$d/server.tmp" && printf %s "$i" > "$d/client-id.tmp" && printf %s "$k" > "$d/client-secret.tmp" && ' +
      'mv "$d/server.tmp" "$d/server" && mv "$d/client-id.tmp" "$d/client-id" && mv "$d/client-secret.tmp" "$d/client-secret"',
      "time-switch-save", root.configDir]
    onStarted: { write(payload); payload = "" }
    onExited: function(code) {
      serverFile.reload(); idFile.reload(); secretFile.reload()
      root.saved(code === 0)
    }
  }
}
