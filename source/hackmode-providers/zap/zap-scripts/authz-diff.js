// zmcp novel plugin: authz-diff.js — access-control differential (Autorize-style).
//
// ZAP's authorization component only detects unauth responses passively;
// this plugin replays ONE request under multiple identities and reports the
// response matrix with similarity scoring (the Autorize idea, our own
// implementation).
//
// Params (JSON in global var zmcp.params):
//   request:    raw HTTP/1.1 request (the privileged original; required)
//   identities: [{name, headers?: {k:v}, removeHeaders?: [k]}] (max 8)
//               name "none"/"unauth"/"anonymous" strips credential headers
//   credentialHeaders: headers treated as credentials (default Authorization, Cookie)
// Result: per-identity status, length, token-similarity vs original,
// denial-shape detection, and a potential-access-issue flag. Full response
// bodies included as evidence.
//
// Authorized lab targets only. POST/PUT/DELETE/PATCH requests repeat the
// action per identity — set identities deliberately.

var ScriptVars = Java.type("org.zaproxy.zap.extension.script.ScriptVars");
var JSystem = java.lang.System;
var HttpSender = Java.type("org.parosproxy.paros.network.HttpSender");
var HttpMessage = Java.type("org.parosproxy.paros.network.HttpMessage");
var HttpRequestHeader = Java.type("org.parosproxy.paros.network.HttpRequestHeader");
var HttpRequestBody = Java.type("org.zaproxy.zap.network.HttpRequestBody");
var sender = new HttpSender(HttpSender.MANUAL_REQUEST_INITIATOR);

var DEFAULT_CRED_HEADERS = ["authorization", "cookie"];

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
  return { status: sm ? Number(sm[1]) : null, body: body, headerText: headerText };
}

function removeHeader(raw, nameLower) {
  var sep = raw.indexOf("\r\n\r\n");
  var lines = raw.substring(0, sep).split(/\r\n/);
  var out = [lines[0]];
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].toLowerCase().indexOf(nameLower + ":") === 0) continue;
    out.push(lines[i]);
  }
  return out.join("\r\n") + "\r\n\r\n" + raw.substring(sep + 4);
}
function replaceHeader(raw, name, value) {
  var sep = raw.indexOf("\r\n\r\n");
  var lines = raw.substring(0, sep).split(/\r\n/);
  var out = [lines[0]];
  var added = false;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].toLowerCase().indexOf(name.toLowerCase() + ":") === 0) {
      if (!added) { out.push(name + ": " + value); added = true; }
      continue;
    }
    out.push(lines[i]);
  }
  if (!added) out.push(name + ": " + value);
  return out.join("\r\n") + "\r\n\r\n" + raw.substring(sep + 4);
}

// Token-set Jaccard similarity, 0-100.
function similarity(a, b) {
  function tok(s) {
    var set = {};
    var m = String(s).toLowerCase().match(/[a-z0-9]{3,}/g) || [];
    for (var i = 0; i < m.length; i++) set[m[i]] = 1;
    var c = 0;
    for (var k in set) c += 1;
    return set;
  }
  var A = tok(a), B = tok(b);
  var inter = 0, aSize = 0, bSize = 0, k;
  for (k in A) { aSize += 1; if (B[k]) inter += 1; }
  for (k in B) bSize += 1;
  var union = aSize + bSize - inter;
  if (union === 0) return 100;
  return Math.round((inter / union) * 100);
}

function isDenialShape(status, body) {
  if (status === 401 || status === 403) return true;
  var low = body.toLowerCase();
  return /sign in|sign-in|login page|please log ?in|unauthorized|forbidden|access denied|authentication required/.test(low);
}

try {
  var P = getParams();
  if (!P.request) throw new Error("params.request is required");
  var identities = P.identities && P.identities.length ? P.identities.slice(0, 8) : [{ name: "none" }];
  var credHeaders = (P.credentialHeaders && P.credentialHeaders.length) ? P.credentialHeaders.map(function (h) { return String(h).toLowerCase(); }) : DEFAULT_CRED_HEADERS;

  var original = sendRaw(String(P.request));

  var matrix = [];
  var issues = [];
  for (var i = 0; i < identities.length; i++) {
    var id = identities[i];
    var name = String(id.name || ("identity-" + i));
    var raw = String(P.request);
    var headersSet = [], headersRemoved = [];
    var isAnon = /none|unauth|anonymous|loggedout/i.test(name);
    if (isAnon) {
      for (var c = 0; c < credHeaders.length; c++) {
        if (new RegExp("^" + credHeaders[c] + ":", "im").test(raw.substring(0, raw.indexOf("\r\n\r\n")))) {
          raw = removeHeader(raw, credHeaders[c]);
          headersRemoved.push(credHeaders[c]);
        }
      }
    }
    var rem = id.removeHeaders || [];
    for (var r = 0; r < rem.length; r++) {
      raw = removeHeader(raw, String(rem[r]).toLowerCase());
      headersRemoved.push(String(rem[r]));
    }
    var hdrs = id.headers || {};
    for (var hk in hdrs) {
      raw = replaceHeader(raw, hk, String(hdrs[hk]));
      headersSet.push(hk);
    }
    // Keep Content-Length consistent with the (unchanged) body: header edits
    // don't touch the body, so no fix-up needed; still re-send as built.
    var resp;
    try {
      resp = sendRaw(raw);
    } catch (e) {
      matrix.push({ identity: name, error: String(e), headersSet: headersSet, headersRemoved: headersRemoved });
      continue;
    }
    var sim = similarity(original.body, resp.body);
    var sameStatus = resp.status === original.status;
    var denial = isDenialShape(resp.status, resp.body);
    var verdict;
    if (sameStatus && sim >= 90) verdict = "identical";
    else if (sim >= 70 && sameStatus) verdict = "similar";
    else verdict = "different";
    var entry = {
      identity: name,
      status: resp.status,
      length: resp.body.length,
      similarity: sim,
      denialShape: denial,
      verdict: verdict,
      headersSet: headersSet,
      headersRemoved: headersRemoved,
      response: { headerText: resp.headerText, body: resp.body },
    };
    if (isAnon && verdict === "identical" && !denial) {
      entry.flag = "potential-access-issue: unauthenticated identity received an identical response";
      issues.push(name);
    }
    matrix.push(entry);
  }

  done({
    ok: true,
    plugin: "authz-diff",
    original: { status: original.status, length: original.body.length, response: { headerText: original.headerText, body: original.body } },
    identitiesRun: identities.length,
    matrix: matrix,
    potentialAccessIssues: issues,
    note: "identical unauthenticated responses that are not denial-shaped are the classic broken-access-control signal — confirm manually",
  });
} catch (e) {
  fail(e, { plugin: "authz-diff" });
}
