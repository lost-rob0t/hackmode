// zmcp novel plugin: race-probe.js — synchronized last-byte racing.
//
// ZAP has no race-condition engine; this is the ZAP-native equivalent of a
// last-byte synchronized release (the HTTP/1.1 technique behind single-packet
// racing): open N raw sockets, send every request except its final byte, then
// release all final bytes back-to-back so the server processes them together.
//
// Params (JSON in global var zmcp.params):
//   request:      raw HTTP/1.1 request template (required unless requests given)
//   requests:     optional array of distinct raw requests (multi-endpoint race)
//   count:        clone count for a single template (default 10, cap 50)
//   host/port:    optional override (default from the Host header)
//   tls:          true = TLS (trust-all; authorized lab targets only)
//   readTimeoutMs: per-socket read deadline (default 5000)
//   holdMs:       pause between head-write phase and release (default 300)
// Result (JSON in global var zmcp.result): per-socket status/length/timing,
// release spread, and a divergence verdict for identical-request races.
//
// Authorized lab targets only. Detection tooling: sends only the operator's
// own request bytes.

var ScriptVars = Java.type("org.zaproxy.zap.extension.script.ScriptVars");
// GraalJS interop note: re-resolving `java.lang.System` per call costs ~18ms;
// hoist every Java reference once (measured 18ms -> 6us per nanoTime call).
var JSystem = java.lang.System;

function getParams() {
  return JSON.parse(ScriptVars.getGlobalVar("zmcp.params") || "{}");
}
function done(result) {
  ScriptVars.setGlobalVar("zmcp.result", JSON.stringify(result));
}
function fail(error, extra) {
  var out = { ok: false, error: String(error) };
  for (var k in (extra || {})) out[k] = extra[k];
  done(out);
}
function nanoMs(t0) { return Math.round((JSystem.nanoTime() - t0) / 1e6); }

var Socket = Java.type("java.net.Socket");
var InetSocketAddress = Java.type("java.net.InetSocketAddress");
var ByteArrayOutputStream = Java.type("java.io.ByteArrayOutputStream");

function trustAllSslFactory() {
  var ctx = java.security.SSLContext.getInstance("TLS");
  var tm = new javax.net.ssl.X509TrustManager({
    checkClientTrusted: function (chain, authType) {},
    checkServerTrusted: function (chain, authType) {},
    getAcceptedIssuers: function () { return null; },
  });
  ctx.init(null, [tm], new java.security.SecureRandom());
  return ctx.getSocketFactory();
}

function parseTarget(raw) {
  var m = /^([A-Za-z]+) (\S+) HTTP\/[\d.]+\r?\n/i.exec(raw);
  if (!m) throw new Error("request must start with 'METHOD path HTTP/1.1'");
  var hm = /^Host:\s*([^\r\n]+)/im.exec(raw);
  if (!hm) throw new Error("request must carry a Host header");
  var host = hm[1].trim(), port = 80;
  var pm = /^(.*):(\d+)$/.exec(host);
  if (pm) { host = pm[1]; port = Number(pm[2]); }
  return { host: host, port: port };
}

function splitLastByte(raw) {
  if (raw.length < 2) throw new Error("request too short");
  var all = new java.lang.String(raw).getBytes("UTF-8");
  var len = all.length;
  var head = java.util.Arrays.copyOfRange(all, 0, len - 1);
  var last = java.util.Arrays.copyOfRange(all, len - 1, len);
  return { head: head, last: last, total: len };
}

// Read until quiet for quietMs, EOF, or deadlineMs. Returns a JS string.
function readResponse(is, quietMs, deadlineMs) {
  var baos = new ByteArrayOutputStream();
  var buf = java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 8192);
  var start = JSystem.nanoTime();
  var total = 0;
  while (total < 1048576) {
    if ((JSystem.nanoTime() - start) / 1e6 > deadlineMs) break;
    var n = 0;
    try { n = is.read(buf); } catch (e) { break; }
    if (n < 0) break;
    baos.write(buf, 0, n);
    total += n;
    if (is.available() === 0) {
      try { java.lang.Thread.sleep(Math.min(quietMs, 20)); } catch (e2) {}
      if (is.available() === 0) break;
    }
  }
  return new java.lang.String(baos.toByteArray(), "UTF-8").toString();
}

function parseStatusLine(resp) {
  var m = /HTTP\/[\d.]+ (\d{3})/.exec(resp);
  return m ? Number(m[1]) : null;
}

try {
  var P = getParams();
  var raws = [];
  if (P.requests && P.requests.length) {
    raws = P.requests.slice(0, 50).map(String);
  } else if (P.request) {
    var n = Math.min(Math.max(Number(P.count) || 10, 2), 50);
    for (var i = 0; i < n; i++) raws.push(String(P.request));
  } else {
    throw new Error("params.request or params.requests is required");
  }
  var tls = !!P.tls;
  var factory = null;
  if (tls) {
    factory = trustAllSslFactory();
  }
  var first = parseTarget(raws[0]);
  var host = P.host ? String(P.host) : first.host;
  var port = P.port !== undefined ? Number(P.port) : (tls ? 443 : first.port);
  var readTimeoutMs = Number(P.readTimeoutMs) || 5000;
  var holdMs = Number(P.holdMs) || 300;

  var split = raws.map(splitLastByte);
  var sockets = [];
  var t0 = JSystem.nanoTime();
  for (var i = 0; i < raws.length; i++) {
    var s;
    if (tls) {
      s = factory.createSocket();
      s.setUseClientMode(true);
    } else {
      s = new Socket();
    }
    s.setTcpNoDelay(true);
    s.setSoTimeout(readTimeoutMs);
    s.connect(new InetSocketAddress(host, port), readTimeoutMs);
    sockets.push(s);
  }
  var connectMs = nanoMs(t0);

  // Phase 1: everything except the final byte.
  for (var i = 0; i < sockets.length; i++) {
    var os = sockets[i].getOutputStream();
    os.write(split[i].head);
    os.flush();
  }
  if (holdMs > 0) java.lang.Thread.sleep(holdMs);

  // Phase 2: release the final bytes back-to-back (sequential writes are
  // microsecond-scale apart on loopback/LAN — the H1 last-byte technique).
  var releases = [];
  var r0 = JSystem.nanoTime();
  for (var i = 0; i < sockets.length; i++) {
    var os = sockets[i].getOutputStream();
    os.write(split[i].last);
    os.flush();
    releases.push((JSystem.nanoTime() - r0) / 1000);
  }
  var releaseSpreadMs = Math.round(releases[releases.length - 1] / 1000 * 100) / 100;

  // Phase 3: read responses.
  var results = [];
  var t1 = JSystem.nanoTime();
  for (var i = 0; i < sockets.length; i++) {
    var resp = "";
    try {
      resp = readResponse(sockets[i].getInputStream(), 150, readTimeoutMs);
    } catch (e) {
      resp = "";
    }
    var status = parseStatusLine(resp);
    results.push({
      i: i,
      status: status,
      length: resp.length,
      ms: nanoMs(t1),
      releaseOffsetUs: Math.round(releases[i] * 100) / 100,
      statusLine: resp.split(/\r?\n/, 1)[0] || "",
    });
    sockets[i].close();
  }

  var statuses = results.map(function (r) { return r.status === null ? "none" : String(r.status); });
  var unique = [];
  for (var i = 0; i < statuses.length; i++) if (unique.indexOf(statuses[i]) < 0) unique.push(statuses[i]);

  var identical = !(P.requests && P.requests.length > 1);
  var verdict;
  if (!identical) {
    verdict = "distinct-requests (compare per-socket statuses yourself)";
  } else if (unique.length <= 1) {
    verdict = "uniform";
  } else {
    verdict = "divergent";
  }

  done({
    ok: true,
    plugin: "race-probe",
    target: { host: host, port: port, tls: tls },
    socketCount: results.length,
    connectMs: connectMs,
    releaseSpreadMs: releaseSpreadMs,
    requestsIdentical: identical,
    uniqueStatuses: unique,
    verdict: verdict,
    results: results,
  });
} catch (e) {
  fail(e, { plugin: "race-probe" });
}
