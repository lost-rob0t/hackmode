// zmcp novel plugin: param-miner.js — differential parameter/header mining.
//
// ZAP has no Param Miner equivalent; this plugin discovers unlinked
// parameters and headers by differential response analysis (the technique
// class of PortSwigger's Param Miner; this is our own implementation).
//
// Params (JSON in global var zmcp.params):
//   request:     raw HTTP/1.1 request (the baseline; required)
//   mode:        query | header | cookie | body | all (default: all)
//   wordlist:    optional array of candidate names (else the embedded list)
//   maxProbes:   probe cap (default 120, max 300)
//   lengthThreshold: body-length delta that counts as a signal (default 8)
//   revalidate:  re-confirm hits with a second round (default true)
// Result: baseline profile, every probe count, and hits with their signals
// (status change / length delta / canary reflection) + response evidence.
//
// Requests go through ZAP's HttpSender (connection settings + recording
// apply). Authorized lab targets only.

var ScriptVars = Java.type("org.zaproxy.zap.extension.script.ScriptVars");
var JSystem = java.lang.System;
var HttpSender = Java.type("org.parosproxy.paros.network.HttpSender");
var HttpMessage = Java.type("org.parosproxy.paros.network.HttpMessage");
var HttpRequestHeader = Java.type("org.parosproxy.paros.network.HttpRequestHeader");
var HttpRequestBody = Java.type("org.zaproxy.zap.network.HttpRequestBody");
var sender = new HttpSender(HttpSender.MANUAL_REQUEST_INITIATOR);

function getParams() { return JSON.parse(ScriptVars.getGlobalVar("zmcp.params") || "{}"); }
function done(result) { ScriptVars.setGlobalVar("zmcp.result", JSON.stringify(result)); }
function fail(error, extra) {
  var out = { ok: false, error: String(error) };
  for (var k in (extra || {})) out[k] = extra[k];
  done(out);
}

function sendRaw(raw) {
  var sep = raw.indexOf("\r\n\r\n");
  if (sep < 0) throw new Error("request missing header/body separator");
  var msg = new HttpMessage(new HttpRequestHeader(raw.substring(0, sep + 2)), new HttpRequestBody(raw.substring(sep + 4)));
  var t0 = JSystem.nanoTime();
  sender.sendAndReceive(msg);
  var body = String(msg.getResponseBody().toString());
  return {
    status: msg.getResponseHeader().getStatusCode(),
    body: body,
    length: body.length,
    ms: Math.round((JSystem.nanoTime() - t0) / 1e6),
  };
}

// Curated candidate list: common unlinked params + behavior-affecting headers.
var DEFAULT_WORDS = [
  "debug", "test", "admin", "user", "id", "email", "redirect", "url", "next", "callback", "return",
  "returnUrl", "returnTo", "path", "dest", "continue", "target", "rurl", "u", "r", "site", "host",
  "lang", "locale", "page", "template", "preview", "view", "theme", "role", "access", "token",
  "secret", "key", "debugMode", "isAdmin", "isadmin", "level", "log", "error", "errors", "show",
  "hide", "format", "json", "debugger", "trace", "verbose", "account", "userId", "userid", "profile",
  "reset", "verify", "confirm", "oauth", "scope", "state", "code", "grant", "client", "response",
  "pricing", "price", "discount", "coupon", "currency", "amount", "quantity", "internal", "mobile",
  "app", "api", "version", "platform", "os", "browser", "proxy", "cdn", "cache", "static", "assets",
  "X-Forwarded-Host", "X-Forwarded-For", "X-Forwarded-Proto", "X-Forwarded-Scheme", "X-Original-URL",
  "X-Rewrite-URL", "X-Host", "X-HTTP-Method-Override", "X-Method-Override", "X-Custom-IP-Authorization",
  "X-Originating-IP", "X-Remote-Addr", "X-Real-IP", "X-Forwarded-Server", "X-Amz-Website-Redirect-Location",
];

function findHeaderEnd(raw) {
  var sep = raw.indexOf("\r\n\r\n");
  return sep;
}
function headerLines(raw) {
  var sep = findHeaderEnd(raw);
  return raw.substring(0, sep).split(/\r\n/);
}
function bodyOf(raw) {
  var sep = findHeaderEnd(raw);
  return raw.substring(sep + 4);
}
function setHeader(raw, name, value) {
  var lines = headerLines(raw);
  var out = [lines[0]];
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].toLowerCase().indexOf(name.toLowerCase() + ":") === 0) continue;
    out.push(lines[i]);
  }
  out.push(name + ": " + value);
  return out.join("\r\n") + "\r\n\r\n" + bodyOf(raw);
}
function appendHeader(raw, name, value) {
  var sep = findHeaderEnd(raw);
  var lines = headerLines(raw);
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].toLowerCase().indexOf(name.toLowerCase() + ":") === 0) {
      lines[i] = lines[i] + "; " + value;
      return lines.join("\r\n") + "\r\n\r\n" + bodyOf(raw);
    }
  }
  return setHeader(raw, name, value);
}
function addQueryParam(raw, name, value) {
  var sep = findHeaderEnd(raw);
  var lines = headerLines(raw);
  var rl = lines[0];
  var m = /^(\w+) (\S+)( HTTP[\d./]+)$/.exec(rl);
  if (!m) throw new Error("cannot parse request line");
  var target = m[2];
  target += (target.indexOf("?") >= 0 ? "&" : "?") + name + "=" + value;
  lines[0] = m[1] + " " + target + m[3];
  return lines.join("\r\n") + "\r\n\r\n" + bodyOf(raw);
}
function addBodyParam(raw, name, value) {
  var body = bodyOf(raw);
  var trimmed = body.replace(/^\s+/, "");
  if (trimmed.indexOf("{") === 0) {
    var inserted = trimmed.replace(/\{/, "{" + JSON.stringify(name) + ":" + JSON.stringify(value) + ",");
    var sep = findHeaderEnd(raw);
    return raw.substring(0, sep + 4) + inserted;
  }
  var withHeader = setHeader(raw, "Content-Type", "application/x-www-form-urlencoded");
  var b = bodyOf(withHeader);
  var newBody = (b.length ? b + "&" : "") + name + "=" + value;
  var lines = headerLines(withHeader);
  var sep2 = findHeaderEnd(withHeader);
  return lines.join("\r\n") + "\r\n\r\n" + newBody;
}

function signalsFor(baseline, variant, canary, lengthThreshold) {
  var sig = [];
  if (variant.status !== baseline.status) sig.push("status:" + variant.status + "!=" + baseline.status);
  var delta = Math.abs(variant.length - baseline.length);
  if (delta >= lengthThreshold) sig.push("lengthDelta:" + delta);
  if (variant.body.indexOf(canary) >= 0) sig.push("reflected");
  return sig;
}

try {
  var P = getParams();
  if (!P.request) throw new Error("params.request is required");
  var base = String(P.request);
  var canary = "zm" + String(JSystem.nanoTime()).slice(-8);
  var mode = P.mode || "all";
  var words = (P.wordlist && P.wordlist.length) ? P.wordlist.map(String) : DEFAULT_WORDS;
  var maxProbes = Math.min(Number(P.maxProbes) || 120, 300);
  var lengthThreshold = Number(P.lengthThreshold) || 8;
  var revalidate = P.revalidate !== false;

  var modes = mode === "all" ? ["query", "header", "cookie"] : [mode];

  // Baseline: two sends for stability.
  var b1 = sendRaw(base);
  var b2 = sendRaw(base);
  var baseline = { status: b1.status, length: b1.length, stable: b1.status === b2.status && Math.abs(b1.length - b2.length) <= 2 };

  var probesSent = 0;
  var truncated = false;
  var hits = [];
  var budget = maxProbes;

  for (var mi = 0; mi < modes.length && budget > 0; mi++) {
    var m = modes[mi];
    for (var wi = 0; wi < words.length && budget > 0; wi++) {
      var name = words[wi];
      var variant;
      try {
        if (m === "query") variant = addQueryParam(base, name, canary);
        else if (m === "header") variant = setHeader(base, name, canary);
        else if (m === "cookie") variant = appendHeader(base, "Cookie", name + "=" + canary);
        else if (m === "body") variant = addBodyParam(base, name, canary);
        else throw new Error("bad mode " + m);
      } catch (e) {
        continue;
      }
      budget -= 1;
      probesSent += 1;
      var res;
      try {
        res = sendRaw(variant);
      } catch (e2) {
        continue;
      }
      var sig = signalsFor(baseline, res, canary, lengthThreshold);
      if (sig.length === 0) continue;
      if (!revalidate) {
        hits.push({ name: name, mode: m, signals: sig, status: res.status, length: res.length, evidence: { body: res.body } });
        continue;
      }
      // Second round: variant again + fresh baseline.
      var res2;
      try { res2 = sendRaw(variant); } catch (e3) { continue; }
      probesSent += 1; budget -= 1;
      var sig2 = signalsFor(baseline, res2, canary, lengthThreshold);
      if (sig2.length === 0) continue;
      hits.push({
        name: name, mode: m, signals: sig2, status: res2.status, length: res2.length,
        confirmed: true,
        evidence: { body: res2.body },
      });
    }
    if (wi >= words.length) { /* exhausted list */ }
    if (budget <= 0 && wi < words.length) truncated = true;
  }

  done({
    ok: true,
    plugin: "param-miner",
    target: headerLines(base)[0],
    baseline: baseline,
    modes: modes,
    probesSent: probesSent,
    wordlistSize: words.length,
    truncated: truncated,
    hits: hits,
    note: hits.length === 0 ? "no differential signals found in this run" : "review signals; reflected canaries are the strongest indicator",
  });
} catch (e) {
  fail(e, { plugin: "param-miner" });
}
