// zmcp novel plugin: smuggle-probe.js — HTTP request smuggling (desync) detection.
//
// ZAP has no desync engine; this plugin probes CL.TE / TE.CL / TE.TE
// desync shapes with timing and leftover-merge oracles over raw sockets
// (the technique class published by HTTP Request Smuggler; this is our own
// implementation and our own technique naming).
//
// Params (JSON in global var zmcp.params):
//   request:    raw HTTP/1.1 request defining the target (method, path, Host).
//               Body-sending probes always POST to the same path.
//   techniques: optional subset of the technique ids below (default: all)
//   timeoutMs:  per-read deadline (default 3000)
//   followPath: path used for the follow-up request (default /zmcp-<random>)
// Result: per-technique verdict + the exact bytes sent and the exact
// responses received (lossless evidence).
//
// Detection tooling: probe payloads are standard research shapes carrying a
// single canary byte; nothing here weaponizes a confirmed desync.

var ScriptVars = Java.type("org.zaproxy.zap.extension.script.ScriptVars");
var JSystem = java.lang.System;

function getParams() { return JSON.parse(ScriptVars.getGlobalVar("zmcp.params") || "{}"); }
function done(result) { ScriptVars.setGlobalVar("zmcp.result", JSON.stringify(result)); }
function fail(error, extra) {
  var out = { ok: false, error: String(error) };
  for (var k in (extra || {})) out[k] = extra[k];
  done(out);
}

var Socket = Java.type("java.net.Socket");
var InetSocketAddress = Java.type("java.net.InetSocketAddress");
var ByteArrayOutputStream = Java.type("java.io.ByteArrayOutputStream");

function parseTarget(raw) {
  var m = /^([A-Za-z]+) (\S+) HTTP\/[\d.]+\r?\n/i.exec(raw);
  if (!m) throw new Error("request must start with 'METHOD path HTTP/1.1'");
  var hm = /^Host:\s*([^\r\n]+)/im.exec(raw);
  if (!hm) throw new Error("request must carry a Host header");
  var host = hm[1].trim(), port = 80, path = m[2];
  var pm = /^(.*):(\d+)$/.exec(host);
  if (pm) { host = pm[1]; port = Number(pm[2]); }
  if (/^https?:\/\//i.test(path)) {
    var u = new java.net.URL(path);
    host = u.getHost();
    port = u.getPort() > 0 ? u.getPort() : (u.getProtocol() === "https" ? 443 : 80);
    path = u.getPath() || "/";
  }
  return { host: host, port: port, path: path };
}

function readResponse(is, deadlineMs) {
  var baos = new ByteArrayOutputStream();
  var buf = java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 8192);
  var start = JSystem.nanoTime();
  var total = 0;
  while (total < 524288) {
    if ((JSystem.nanoTime() - start) / 1e6 > deadlineMs) break;
    var n = 0;
    try { n = is.read(buf); } catch (e) { break; }
    if (n < 0) break;
    baos.write(buf, 0, n);
    total += n;
    if (is.available() === 0) {
      try { java.lang.Thread.sleep(15); } catch (e2) {}
      if (is.available() === 0) break;
    }
  }
  return new java.lang.String(baos.toByteArray(), "UTF-8").toString();
}

function statusOf(resp) {
  var m = /HTTP\/[\d.]+ (\d{3})/.exec(resp);
  return m ? Number(m[1]) : null;
}

// Open a socket, send `probeBytes` fully, read response1, send `followBytes`,
// read response2. Returns both transcripts and timings.
function probeOnce(host, port, probeBytes, followBytes, timeoutMs) {
  var s = new Socket();
  s.setTcpNoDelay(true);
  s.setSoTimeout(timeoutMs);
  try {
    s.connect(new InetSocketAddress(host, port), timeoutMs);
    var os = s.getOutputStream();
    var t0 = JSystem.nanoTime();
    os.write(probeBytes); os.flush();
    var resp1 = readResponse(s.getInputStream(), timeoutMs);
    var probeMs = Math.round((JSystem.nanoTime() - t0) / 1e6);
    var t1 = JSystem.nanoTime();
    os.write(followBytes); os.flush();
    var resp2 = readResponse(s.getInputStream(), timeoutMs);
    var followMs = Math.round((JSystem.nanoTime() - t1) / 1e6);
    return { resp1: resp1, resp2: resp2, probeMs: probeMs, followMs: followMs };
  } finally {
    try { s.close(); } catch (e) {}
  }
}

function timingOnce(host, port, probeBytes, timeoutMs) {
  var s = new Socket();
  s.setTcpNoDelay(true);
  s.setSoTimeout(timeoutMs);
  try {
    s.connect(new InetSocketAddress(host, port), timeoutMs);
    var os = s.getOutputStream();
    var t0 = JSystem.nanoTime();
    os.write(probeBytes); os.flush();
    var resp = readResponse(s.getInputStream(), timeoutMs);
    return { resp: resp, ms: Math.round((JSystem.nanoTime() - t0) / 1e6) };
  } finally {
    try { s.close(); } catch (e) {}
  }
}

function req(method, path, hostHeader, extraHeaders, body) {
  var lines = [method + " " + path + " HTTP/1.1", "Host: " + hostHeader];
  for (var k in extraHeaders) lines.push(k + ": " + extraHeaders[k]);
  lines.push("Connection: keep-alive");
  var head = lines.join("\r\n") + "\r\n\r\n";
  return head + (body || "");
}

// The technique catalog. ids are stable; the MCP tool exposes them.
function techniques(host, port, path, hostHeader, canary, followPath) {
  var T = [];
  var b4 = "1\r\nZ\r\n0\r\n\r\n";
  var cl4 = String(b4.length - 2); // CL covering "1\r\nZ" exactly

  // Timing oracles: a desync-prone back-end stalls on the truncated stream.
  T.push({
    id: "timing-cl-te",
    semantics: "CL covers '1\\r\\nZ'; if the back-end honors chunked it waits for the chunk terminator (delay oracle).",
    kind: "timing",
    bytes: req("POST", path, hostHeader, { "Content-Length": cl4, "Transfer-Encoding": "chunked" }, b4),
    follow: null,
  });
  var b5 = "0\r\n\r\n";
  T.push({
    id: "timing-te-cl",
    semantics: "TE: chunked with CL 3 bytes past the terminator; if the back-end honors CL it waits for phantom bytes (delay oracle).",
    kind: "timing",
    bytes: req("POST", path, hostHeader, { "Content-Length": String(b5.length + 3), "Transfer-Encoding": "chunked" }, b5),
    follow: null,
  });

  // Leftover-merge oracles: a leftover canary byte must corrupt the next request.
  var mergeBody = "0\r\n\r\n" + canary;
  T.push({
    id: "merge-cl-te",
    semantics: "CL covers '0\\r\\n\\r\\n" + canary + "'; back-end chunked ends early, '" + canary + "' merges into the follow-up request.",
    kind: "merge",
    bytes: req("POST", path, hostHeader, { "Content-Length": String(mergeBody.length), "Transfer-Encoding": "chunked" }, mergeBody),
    follow: req("GET", followPath, hostHeader, {}, ""),
  });
  T.push({
    id: "merge-te-cl",
    semantics: "TE ends at the terminator; CL says 5 bytes. If the front-end is chunked-aware the '" + canary + "' stays local and merges into the follow-up.",
    kind: "merge",
    bytes: req("POST", path, hostHeader, { "Content-Length": "5", "Transfer-Encoding": "chunked" }, mergeBody),
    follow: req("GET", followPath, hostHeader, {}, ""),
  });

  // TE.TE obfuscations: conflicting TE headers; whichever parser bends first
  // shows up as a merge/timing anomaly, attributing the desync direction.
  var obfs = [
    { id: "merge-tete-xchunked", te: "chunked\r\nTransfer-Encoding: xchunked", semantics: "second TE value 'xchunked' is invalid for strict parsers." },
    { id: "merge-tete-space", te: " chunked", semantics: "leading space before 'chunked' breaks some parsers." },
    { id: "merge-tete-tab", te: "chunked\t", semantics: "trailing tab after 'chunked' breaks some parsers." },
  ];
  for (var i = 0; i < obfs.length; i++) {
    var o = obfs[i];
    var headers = { "Content-Length": String(mergeBody.length), "Transfer-Encoding": o.te };
    T.push({
      id: o.id,
      semantics: o.semantics,
      kind: "merge",
      bytes: req("POST", path, hostHeader, headers, mergeBody),
      follow: req("GET", followPath, hostHeader, {}, ""),
    });
  }
  return T;
}

function classifyMerge(r, followStatusBaseline, canary, timeoutHit1, timeoutHit2) {
  var st1 = statusOf(r.resp1), st2 = statusOf(r.resp2);
  var reflected = r.resp2.indexOf(canary + "GET") >= 0 || r.resp1.indexOf(canary + "GET") >= 0;
  var anomalous2 = st2 !== null && st2 >= 400;
  var lost2 = timeoutHit2 || st2 === null;
  var evidence = {
    resp1Status: st1, resp2Status: st2,
    resp1Bytes: r.resp1, resp2Bytes: r.resp2,
    probeMs: r.probeMs, followMs: r.followMs,
    canaryMethodMerged: reflected,
  };
  if (reflected || anomalous2 || lost2) return { verdict: "desync-indicated", evidence: evidence };
  return { verdict: "no-desync", evidence: evidence };
}

try {
  var P = getParams();
  if (!P.request) throw new Error("params.request is required");
  var target = parseTarget(String(P.request));
  var timeoutMs = Number(P.timeoutMs) || 3000;
  var canary = "G";
  var rnd = String(JSystem.nanoTime()).slice(-6);
  var followPath = P.followPath ? String(P.followPath) : "/zmcp-smuggle-" + rnd;
  var hostHeader = P.host ? String(P.host) : (target.host + (target.port ? ":" + target.port : ""));

  // Baseline: plain GET for status/latency calibration.
  var base = timingOnce(target.host, target.port, req("GET", "/", hostHeader, {}, ""), timeoutMs);
  var baseline = { status: statusOf(base.resp), ms: base.ms, resp: base.resp };

  var all = techniques(target.host, target.port, target.path, hostHeader, canary, followPath);
  var wanted = P.techniques && P.techniques.length
    ? all.filter(function (t) { return P.techniques.indexOf(t.id) >= 0; })
    : all;
  if (wanted.length === 0) throw new Error("no matching technique ids; valid: " + all.map(function (t) { return t.id; }).join(", "));

  var results = [];
  var anyDesync = false;
  for (var i = 0; i < wanted.length; i++) {
    var t = wanted[i];
    var t0 = JSystem.nanoTime();
    try {
      var fb = t.follow ? new java.lang.String(t.follow).getBytes("UTF-8") : null;
      var pb = new java.lang.String(t.bytes).getBytes("UTF-8");
      if (t.kind === "timing") {
        var r = timingOnce(target.host, target.port, pb, timeoutMs);
        var st = statusOf(r.resp);
        var stalled = r.ms > Math.max(1200, baseline.ms * 3);
        var entry = {
          id: t.id, semantics: t.semantics, request: t.bytes,
          ms: r.ms, baselineMs: baseline.ms, status: st, stalled: stalled,
          response: r.resp,
          verdict: stalled ? "desync-indicated" : "no-desync",
        };
        if (stalled) anyDesync = true;
        results.push(entry);
      } else {
        var r2 = probeOnce(target.host, target.port, pb, fb, timeoutMs);
        var cls = classifyMerge(r2, baseline.status, canary, false, false);
        var entry2 = {
          id: t.id, semantics: t.semantics, request: t.bytes, followUp: t.follow,
          baselineStatus: baseline.status,
          verdict: cls.verdict, evidence: cls.evidence,
        };
        if (cls.verdict === "desync-indicated") anyDesync = true;
        results.push(entry2);
      }
    } catch (e) {
      results.push({ id: t.id, verdict: "inconclusive", error: String(e) });
    }
  }

  done({
    ok: true,
    plugin: "smuggle-probe",
    target: { host: target.host, port: target.port, path: target.path },
    baseline: baseline,
    techniquesRun: results.map(function (r) { return r.id; }),
    desyncIndicated: anyDesync,
    verdict: anyDesync ? "desync-indicated (review per-technique evidence)" : "no-desync detected",
    results: results,
  });
} catch (e) {
  fail(e, { plugin: "smuggle-probe" });
}
