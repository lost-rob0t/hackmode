// zmcp novel plugin: graphql-probe.js — GraphQL deep probing (InQL technique class).
//
// ZAP's graphql add-on imports schemas and scans, but has no POI scan,
// cycle scan, batch-alias generation, suggestion oracle, or engine
// fingerprinting; this plugin implements those (the InQL technique class;
// our own implementation).
//
// Params (JSON in global var zmcp.params):
//   url:       GraphQL endpoint (required)
//   headers:   optional {k:v} merged into every request
//   mode:      introspect | suggestions | poi | cycles | batch | fingerprint
//              (default introspect)
//   schema:    optional pre-fetched introspection result (poi/cycles reuse it)
//   maxDepth:  POI shortest-path depth cap (default 6)
//   maxCycles: cycle cap (default 20), depth cap 8
//   template:  batch template with $[INT:a:b] or $[LIST|x|y] placeholders
//   kind:      batch operation kind query|mutation (default query)
//   send:      batch mode actually sends when true (default false: generate only)
// Result: per-mode JSON with lossless evidence (exact queries + responses).
//
// Authorized lab targets only. Batch documents are generated to fail
// validation on compliant servers unless the operator asks for send.

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

// POST one GraphQL document. Returns {status, body, ms}.
function gql(url, headers, query) {
  var payload = JSON.stringify({ query: query });
  var lines = ["POST " + pathOf(url) + " HTTP/1.1", "Host: " + hostOf(url),
               "Content-Type: application/json", "Accept: application/json",
               "Content-Length: " + payload.length, "Connection: close"];
  for (var k in (headers || {})) lines.push(k + ": " + headers[k]);
  var raw = lines.join("\r\n") + "\r\n\r\n" + payload;
  var sep = raw.indexOf("\r\n\r\n");
  var msg = new HttpMessage(new HttpRequestHeader(raw.substring(0, sep + 2)), new HttpRequestBody(raw.substring(sep + 4)));
  var t0 = JSystem.nanoTime();
  sender.sendAndReceive(msg);
  return {
    status: msg.getResponseHeader().getStatusCode(),
    body: String(msg.getResponseBody().toString()),
    ms: Math.round((JSystem.nanoTime() - t0) / 1e6),
    query: query,
  };
}
function pathOf(u) {
  var m = /^https?:\/\/[^\/]+(\/.*)$/.exec(u);
  return m ? m[1] : "/";
}
function hostOf(u) {
  var m = /^https?:\/\/([^\/]+)/.exec(u);
  return m ? m[1] : "";
}

// Minimal full introspection document (ofType nesting covers wrappers).
var INTROSPECTION =
  "query zmcpIntrospection { __schema { queryType { name } mutationType { name } subscriptionType { name } " +
  "types { kind name description fields(includeDeprecated: true) { name isDeprecated deprecationReason " +
  "args { name defaultValue type { ...TypeRef } } type { ...TypeRef } } inputFields { name defaultValue type { ...TypeRef } } " +
  "enumValues { name isDeprecated deprecationReason } interfaces { ...TypeRef } possibleTypes { ...TypeRef } } } } " +
  "fragment TypeRef on __Type { kind name ofType { kind name ofType { kind name ofType { kind name " +
  "ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } }";

// Fetch + cache the schema; returns the parsed introspection or an error shape.
function fetchSchema(url, headers, provided) {
  if (provided) return { ok: true, schema: provided };
  var r = gql(url, headers, INTROSPECTION);
  var parsed = null;
  try { parsed = JSON.parse(r.body); } catch (e) {}
  if (!parsed || !parsed.data || !parsed.data.__schema) {
    return { ok: false, response: r, hint: "introspection disabled or not GraphQL — try mode=suggestions" };
  }
  return { ok: true, schema: parsed.data.__schema, response: r };
}

// Type graph helpers over an introspection result.
function typeIndex(schema) {
  var idx = {};
  var types = schema.types || [];
  for (var i = 0; i < types.length; i++) idx[types[i].name] = types[i];
  return idx;
}
function unwrapped(type) {
  while (type && type.ofType) type = type.ofType;
  return type;
}

var POI_KEYWORDS = ["auth", "password", "passwd", "email", "token", "secret", "admin", "role",
                    "permission", "ssn", "card", "payment", "invoice", "billing", "file", "url",
                    "address", "phone", "debug", "internal", "config", "apikey", "api_key", "key",
                    "private", "upload", "exec", "query"];

// POI scan: security-relevant fields at their shortest query path.
function poiScan(schema, maxDepth) {
  var idx = typeIndex(schema);
  var findings = [];
  var roots = [];
  if (schema.queryType) roots.push({ type: schema.queryType.name, prefix: "query" });
  if (schema.mutationType) roots.push({ type: schema.mutationType.name, prefix: "mutation" });
  // BFS from root fields: path is field names joined.
  var queue = [];
  for (var r = 0; r < roots.length; r++) {
    var rootType = idx[roots[r].type];
    var fields = (rootType && rootType.fields) || [];
    for (var f = 0; f < fields.length; f++) {
      queue.push({ type: unwrapped(fields[f].type).name, path: fields[f].name, root: roots[r].prefix });
    }
  }
  var seenPaths = {};
  var guard = 0;
  while (queue.length && findings.length < 100 && guard < 5000) {
    guard += 1;
    var node = queue.shift();
    if (seenPaths[node.path]) continue;
    seenPaths[node.path] = 1;
    var depth = node.path.split(".").length;
    if (depth > maxDepth) continue;
    var t = idx[node.type];
    var fields = (t && t.fields) || [];
    for (var fi = 0; fi < fields.length; fi++) {
      var field = fields[fi];
      var childPath = node.path + "." + field.name;
      var low = field.name.toLowerCase();
      for (var k = 0; k < POI_KEYWORDS.length; k++) {
        if (low.indexOf(POI_KEYWORDS[k]) >= 0) {
          findings.push({
            keyword: POI_KEYWORDS[k],
            root: node.root,
            path: childPath,
            fieldType: unwrapped(field.type).name,
            deprecated: !!field.isDeprecated,
            example: buildExample(node.root, childPath),
          });
          break;
        }
      }
      var child = idx[unwrapped(field.type).name];
      if (child && (child.kind === "OBJECT") && depth < maxDepth) {
        queue.push({ type: child.name, path: childPath, root: node.root });
      }
    }
  }
  return { pois: findings, truncated: guard >= 5000 };
}

// Simple readable example: root { a { b { c } } }
function buildExample(root, path) {
  var parts = path.split(".");
  var out = root + " {";
  for (var i = 0; i < parts.length; i++) out += " " + parts[i] + " {";
  out += "}";
  for (var i = 0; i < parts.length; i++) out += " }";
  return out;
}

// Cycles: simple cycles in the object-type graph, shortest first.
function cyclesScan(schema, maxCycles) {
  var idx = typeIndex(schema);
  var names = [];
  for (var n in idx) {
    if (idx[n].kind === "OBJECT" && n.indexOf("__") !== 0) names.push(n);
  }
  names.sort();
  var cycles = [];
  for (var i = 0; i < names.length && cycles.length < maxCycles; i++) {
    var start = names[i];
    // DFS paths back to start, depth cap 8.
    var stack = [{ node: start, path: [start] }];
    var localGuard = 0;
    while (stack.length && cycles.length < maxCycles && localGuard < 2000) {
      localGuard += 1;
      var cur = stack.pop();
      if (cur.path.length > 8) continue;
      var t = idx[cur.node];
      var fields = (t && t.fields) || [];
      for (var f = 0; f < fields.length; f++) {
        var next = unwrapped(fields[f].type).name;
        if (next === start) {
          cycles.push({ types: cur.path.concat([start]), length: cur.path.length });
          break;
        }
        if (idx[next] && idx[next].kind === "OBJECT" && cur.path.indexOf(next) < 0) {
          stack.push({ node: next, path: cur.path.concat([next]) });
        }
      }
    }
  }
  var cyclicTypes = {};
  for (var c = 0; c < cycles.length; c++) for (var t2 = 0; t2 < cycles[c].types.length; t2++) cyclicTypes[cycles[c].types[t2]] = 1;
  var list = [];
  for (var ct in cyclicTypes) list.push(ct);
  return { cycles: cycles, cyclicTypes: list, truncated: cycles.length >= maxCycles };
}

// Batch alias expansion: $[INT:a:b] numeric, $[LIST|x|y] element-wise.
function expandBatch(template) {
  var docs = [];
  var intM = /\$\[INT:(-?\d+):(-?\d+)(?::(-?\d+))?\]/.exec(template);
  var listM = /\$\[LIST\|([^\]]+)\]/.exec(template);
  var count = 0;
  if (intM) {
    var from = Number(intM[1]), to = Number(intM[2]), step = Number(intM[3] || 1);
    var aliases = [];
    for (var v = from; v <= to && count < 10000; v += step) {
      aliases.push("a" + count + ":" + template.replace(intM[0], String(v)));
      count += 1;
    }
    docs.push(aliases);
  } else if (listM) {
    var items = listM[1].split("|");
    var aliases2 = [];
    for (var li = 0; li < items.length && count < 10000; li++) {
      aliases2.push("a" + li + ":" + template.replace(listM[0], items[li]));
      count += 1;
    }
    docs.push(aliases2);
  } else {
    throw new Error("template needs $[INT:from:to(:step)] or $[LIST|x|y|...]");
  }
  return docs[0];
}

// Engine fingerprint hints from malformed-query error signatures (heuristics).
function fingerprintProbes(url, headers) {
  var probes = [
    { id: "brace", query: "{" },
    { id: "unknown-field", query: "{ zmcpNoSuchField }" },
    { id: "bad-directive", query: "query @zmcpBad { __typename }" },
  ];
  var out = [];
  for (var i = 0; i < probes.length; i++) {
    var r = gql(url, headers, probes[i].query);
    var body = r.body;
    var hints = [];
    if (body.indexOf("Did you mean") >= 0) hints.push("suggestion-oracle");
    if (body.indexOf("SYNTAX_ERROR") >= 0 || body.indexOf("GraphQLError") >= 0) hints.push("graphql-java-shape");
    if (body.indexOf("GRAPHQL_VALIDATION_FAILED") >= 0) hints.push("apollo-shape");
    if (body.indexOf("validation failed") >= 0) hints.push("hasura-shape");
    if (body.indexOf("cannot query field") >= 0) hints.push("graphql-js-shape");
    out.push({ probe: probes[i].id, status: r.status, ms: r.ms, hints: hints, response: body });
  }
  return out;
}

try {
  var P = getParams();
  if (!P.url) throw new Error("params.url is required");
  var url = String(P.url);
  if (!/^https?:\/\//.test(url)) throw new Error("url must be http(s)");
  var headers = P.headers || {};
  var mode = P.mode || "introspect";

  if (mode === "introspect") {
    var s = fetchSchema(url, headers, null);
    if (!s.ok) done({ ok: true, plugin: "graphql-probe", mode: mode, introspectionEnabled: false, hint: s.hint, response: s.response });
    else done({ ok: true, plugin: "graphql-probe", mode: mode, introspectionEnabled: true, schema: s.schema });
  } else if (mode === "suggestions") {
    var r = gql(url, headers, "{ zmcpNoSuchField }");
    var m = /Did you mean ([^?]+)\?/.exec(r.body);
    var suggestions = m ? m[1].split(/ or /).map(function (x) { return x.replace(/^"|"$/g, ""); }) : [];
    done({ ok: true, plugin: "graphql-probe", mode: mode, suggestionOracle: m !== null, suggestions: suggestions, response: r });
  } else if (mode === "poi") {
    var s2 = fetchSchema(url, headers, P.schema);
    if (!s2.ok) done({ ok: false, error: "no schema available for POI scan", hint: s2.hint, response: s2.response });
    else {
      var poi = poiScan(s2.schema, Math.min(Number(P.maxDepth) || 6, 10));
      poi.exampleQueryFix = null;
      done({ ok: true, plugin: "graphql-probe", mode: mode, poiCount: poi.pois.length, pois: poi.pois, truncated: poi.truncated });
    }
  } else if (mode === "cycles") {
    var s3 = fetchSchema(url, headers, P.schema);
    if (!s3.ok) done({ ok: false, error: "no schema available for cycle scan", hint: s3.hint });
    else {
      var cy = cyclesScan(s3.schema, Math.min(Number(P.maxCycles) || 20, 50));
      done({ ok: true, plugin: "graphql-probe", mode: mode, cycleCount: cy.cycles.length, cycles: cy.cycles, cyclicTypes: cy.cyclicTypes, truncated: cy.truncated });
    }
  } else if (mode === "batch") {
    if (!P.template) throw new Error("batch mode needs params.template");
    var aliases = expandBatch(String(P.template));
    var kind = (P.kind === "mutation") ? "mutation" : "query";
    var doc = kind + " zmcpBatch { " + aliases.join(" ") + " }";
    var result = { ok: true, plugin: "graphql-probe", mode: mode, aliasCount: aliases.length, document: doc, sent: false };
    if (P.send === true) {
      var rr = gql(url, headers, doc);
      result.sent = true;
      result.response = rr;
    }
    done(result);
  } else if (mode === "fingerprint") {
    done({ ok: true, plugin: "graphql-probe", mode: mode, probes: fingerprintProbes(url, headers) });
  } else {
    throw new Error("unknown mode " + mode + " (introspect|suggestions|poi|cycles|batch|fingerprint)");
  }
} catch (e) {
  fail(e, { plugin: "graphql-probe" });
}
