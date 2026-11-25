// zmcp novel plugin: content-discovery.js — dictionary-driven path discovery.
//
// ZAP's retired forced-browse add-on left a gap; this plugin discovers
// unlinked content with a wordlist plus soft-404 discrimination (random-path
// baselines and response-shape clustering — the standard content-discovery
// method, our own implementation).
//
// Params (JSON in global var zmcp.params):
//   baseUrl:    http(s)://host[:port]/base/ (required, or request template)
//   request:    raw request template containing {PATH} (alternative to baseUrl)
//   wordlist:   optional array of path words (else the embedded list)
//   extensions: optional array like ["php","bak","json"] appended to words
//   maxProbes:  probe cap (default 200, max 500)
// Result: soft-404 baseline, found paths with status/length/redirect, and
// the probe count. Full lossless evidence per hit.
//
// Authorized lab targets only.

var ScriptVars = Java.type("org.zaproxy.zap.extension.script.ScriptVars");
var JSystem = java.lang.System;
var HttpSender = Java.type("org.parosproxy.paros.network.HttpSender");
var HttpMessage = Java.type("org.parosproxy.paros.network.HttpMessage");
var HttpRequestHeader = Java.type("org.parosproxy.paros.network.HttpRequestHeader");
var HttpRequestBody = Java.type("org.zaproxy.zap.network.HttpRequestBody");
var sender = new HttpSender(HttpSender.MANUAL_REQUEST_INITIATOR);

var DEFAULT_WORDS = [
  "admin", "administrator", "api", "api/v1", "api/v2", "backup", "backups", "bak", "bin", "config",
  "configuration", "console", "dashboard", "db", "debug", "dev", "docs", "env", "files", "ftp",
  "git", "graphql", "home", "images", "img", "install", "jenkins", "js", "json", "legacy", "login",
  "logout", "logs", "mail", "manage", "manager", "media", "metrics", "old", "panel", "phpinfo",
  "phpmyadmin", "private", "profile", "register", "reports", "restore", "robots.txt", "rss", "search",
  "secret", "server-status", "settings", "setup", "sitemap.xml", "sql", "src", "staging", "stat",
  "static", "stats", "status", "swagger", "swagger.json", "sys", "system", "temp", "test", "tmp",
  "tools", "uploads", "user", "users", "vendor", "web.config", "wp-admin", "wp-content", "wp-login.php",
  "www", ".env", ".git/config", ".git/HEAD", ".htaccess", ".svn/entries", "crossdomain.xml",
  "security.txt", "actuator", "health", "info", "monitor", "version", "openapi.json", "graphql.json",
];

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
  sender.sendAndReceive(msg);
  var body = String(msg.getResponseBody().toString());
  var headerText = String(msg.getResponseHeader().toString());
  var sm = /HTTP\/[\d.]+ (\d{3})/.exec(headerText);
  var loc = /Location:\s*([^\r\n]+)/i.exec(headerText);
  return { status: sm ? Number(sm[1]) : null, body: body, length: body.length, location: loc ? loc[1].trim() : null };
}

function buildTemplate(P) {
  if (P.request) return String(P.request);
  if (!P.baseUrl) throw new Error("params.baseUrl or params.request is required");
  var u = new java.net.URL(String(P.baseUrl));
  var port = u.getPort() > 0 ? u.getPort() : (u.getProtocol() === "https" ? 443 : 80);
  var hostHeader = u.getHost() + (u.getPort() > 0 ? ":" + u.getPort() : "");
  var base = u.getPath();
  if (!/\/$/.test(base)) base += "/";
  return "GET " + base + "{PATH} HTTP/1.1\r\nHost: " + hostHeader + "\r\nConnection: close\r\n\r\n";
}

try {
  var P = getParams();
  var template = buildTemplate(P);
  var words = (P.wordlist && P.wordlist.length) ? P.wordlist.map(String) : DEFAULT_WORDS;
  var extensions = (P.extensions && P.extensions.length) ? P.extensions.map(String) : [];
  var maxProbes = Math.min(Number(P.maxProbes) || 200, 500);

  var candidates = [];
  for (var i = 0; i < words.length; i++) {
    candidates.push(words[i].replace(/^\/+/, ""));
    for (var e = 0; e < extensions.length; e++) candidates.push(words[i].replace(/^\/+/, "") + "." + extensions[e]);
  }
  var truncated = candidates.length > maxProbes;
  candidates = candidates.slice(0, maxProbes);

  // Soft-404 baseline: two random paths.
  var rnd = String(JSystem.nanoTime());
  var bl1 = sendRaw(template.replace("{PATH}", "zmcp-nonexistent-" + rnd.slice(-8)));
  var bl2 = sendRaw(template.replace("{PATH}", "zmcp-nonexistent-" + rnd.slice(3, 11)));
  var baseline = {
    statuses: [bl1.status, bl2.status],
    lengths: [bl1.length, bl2.length],
    lenSpread: Math.abs(bl1.length - bl2.length),
  };

  var found = [];
  var probesSent = 0;
  for (var c = 0; c < candidates.length; c++) {
    var word = candidates[c];
    var res;
    try {
      res = sendRaw(template.replace("{PATH}", word));
    } catch (e) {
      continue;
    }
    probesSent += 1;
    var interesting = false;
    var why = null;
    if (res.status >= 200 && res.status < 300) { interesting = true; why = "2xx"; }
    else if (res.status === 401 || res.status === 403) { interesting = true; why = "auth-gated"; }
    else if (res.status >= 300 && res.status < 400) { interesting = true; why = "redirect"; }
    else if (res.status === bl1.status && Math.abs(res.length - bl1.length) >= 40) { interesting = true; why = "soft-404-shape-differs"; }
    if (!interesting) continue;
    found.push({
      path: word, status: res.status, length: res.length,
      reason: why, redirectLocation: res.location,
      evidence: { headerText: res.headerText.slice(0, 2000), body: res.body },
    });
  }

  done({
    ok: true,
    plugin: "content-discovery",
    baseline: baseline,
    probesSent: probesSent,
    candidateCount: candidates.length,
    truncated: truncated,
    found: found,
  });
} catch (e) {
  fail(e, { plugin: "content-discovery" });
}
