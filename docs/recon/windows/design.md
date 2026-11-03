# StarIntel Windows Network Recon Actor Set — Design

Status: DESIGN (no implementation). Target repo: `starintel-network` (new, Forgejo
`lost-rob0t/starintel-network`, origin at `git.starintel.actor`).

Source instruction: operator chat instruction 2026-09-19 — *"design issue slices
for a windows network recon actor set (all actors must also have cli tool forms
that uses rabbitmq) like smb, active directory"*.

Reference anatomy: `/home/unseen/starintel/starintel-pro-actors` (read-only; do
not modify). The contract studied: `README.md`,
`python/src/starintel_pro_actors/manifests.py`,
`python/src/starintel_pro_actors/star_server_transport.py`,
`python/src/starintel_pro_actors/userhunt.py`,
`python/src/starintel_pro_actors/star_server_youtube.py`,
`python/src/starintel_pro_actors/youtube/cli.py`.

---

## 1. Spec authority and versioning (fail-closed)

- The canonical schema repository (`lost-rob0t/starintel-gpt-auto-dig`) is
  currently at release **0.9.2** (`starintel-network-capture` profile; verified
  2026-09-19 via `scripts/schema-release.py current`). The **0.10.1** dtypes this
  design consumes (`host` enriched, `network-device`, `relation`,
  `observation`, `source`) are being **minted in parallel** and are not yet in
  the local canonical checkout.
- Therefore this design treats the field lists below as
  **normative-from-operator-instruction**, and the first slice (NET-001) is
  **blocked until the canonical 0.10.1 release is minted**. NET-001 pins
  `starintel-network/schema/starintel-schema.lock.json` to the canonical
  release commit, and every actor slice MUST reconcile its emitted fields
  against the minted schema + `starintel_doc` validators before merge. If the
  minted names differ from this document, the minted schema wins and the actor
  slice records the delta in its issue.
- Wire documents carry the immutable base `schema_version` of the 0.10 line
  with the lock resolving the active release (mirroring pro-actors: envelope
  `schema_version: "0.9.0"` base family + `release_version` from lock). Exact
  values come from the lock; never from this file.
- Predicate vocabulary available: `communicates_with`, `connected_to`,
  `hosted_on`, `member_of`, `employed_by`, `resolves_to`, `managed_by`. This
  design proposes **no new predicates** — the given set covers all modeled
  edges (see §6 mapping).

## 2. What this fleet is

A Python Pykka actor fleet in a new repo `starintel-network` that performs
**unauthenticated (recon-only) Windows/AD network discovery** against operator
authorized ranges, converts probe responses into StarIntel 0.10.1 documents
(`host`, `network-device`, `relation`, `observation`, `source`), validates them
against the pinned schema, and publishes them to RabbitMQ
`documents.ingest.<dtype>` with publisher confirms — exactly the
pro-actors contract.

Mandatory invariant (operator): **every actor ships in two forms — a daemon
(Pykka service consuming `documents.target.dispatch.<actor>`) and a CLI
(`starnet <actor> <subcommand>`)** — and both forms share one handler, one
validator, one publisher. The forms differ only in intake (queue vs argv),
never in document construction, validation, or publishing.

### Non-goals (binding)

- No exploitation, no vulnerability abuse (no PrintNightmare/Zerologon/SMBGhost
  probing beyond protocol negotiation that a legitimate client performs).
- No relay attacks (no Responder-style poisoning, no ntlmrelayx).
- No credential guessing: no password spray, no brute force, no hash cracking.
- No file **content** download from shares (share-scraper records names/sizes
  only; hard rule).
- No credential storage, cache, or persistence in this design. Authenticated
  modes arrive later as separate approved work; this design only defines the
  seams (`CredentialProviderPort`) with no live implementation.
- No writes to targets. No SMB tree connect with write intents, no LDAP
  modifies, no DNS dynamic updates.
- No denial-of-service shaped probing (no connection floods, no oversized
  negotiate buffers).

## 3. Repository anatomy

Mirrors `starintel-pro-actors` (imported patterns, not code sharing — the
transport/registry pattern is small enough to own per-repo, and pro-actors must
not be modified):

```text
starintel-network/
├── python/
│   ├── pyproject.toml            # package: starintel-network, extras: amqp, dev
│   ├── src/starintel_network/
│   │   ├── __init__.py
│   │   ├── actor.py              # Pykka facade Actor/ActorSystem (pro-actors pattern)
│   │   ├── transport.py          # RabbitMQ boundary: Pika consumer thread, publisher
│   │   │                         #   confirms, ACK-after-all-outputs-confirmed, retry policy
│   │   ├── schema_boundary.py    # pinned 0.10 lock -> starintel_doc validate_document
│   │   ├── registry.py           # ActorServiceRegistration per family (conformance gate)
│   │   ├── manifests.py          # ACTOR_MANIFESTS (ActorManifestSpec-compatible)
│   │   ├── runner.py             # THE dual-form runner (see §4)
│   │   ├── probes/               # shared probe support (§5)
│   │   ├── docs/                 # document builders: host/relation/observation/source
│   │   ├── cli.py                # starnet umbrella typer app
│   │   ├── smb_recon.py          # one module per actor family
│   │   ├── ad_ldap_recon.py
│   │   ├── kerberos_recon.py
│   │   ├── dns_recon.py
│   │   ├── netbios_recon.py
│   │   ├── winrm_probe.py
│   │   ├── msrpc_probe.py
│   │   ├── ntlm_fingerprint.py
│   │   ├── share_scraper.py
│   │   └── host_targets.py       # router actor
│   ├── tests/                    # hermetic unit + conformance + container coverage
│   ├── t/                         # live broker / live lab (env opt-in)
│   └── nix/
├── docker/Dockerfile             # named target per runnable actor
├── compose.yaml                  # whole fleet; broker healthcheck gating
├── schema/starintel-schema.lock.json   # 0.10.x release pin (NET-001)
└── docs/                          # per-actor org guides
```

Naming: CLI binary `starnet`; package `starintel-network`; python module
`starintel_network`; actor ids exactly `smb-recon`, `ad-ldap-recon`,
`kerberos-recon`, `dns-recon`, `netbios-recon`, `winrm-probe`, `msrpc-probe`,
`ntlm-fingerprint`, `share-scraper`, `host-targets`.

## 4. Runtime, transport, and the dual-form invariant

### 4.1 Transport contract (identical semantics to pro-actors)

- Topic exchange `documents` (durable). Daemon consumes
  `documents.target.dispatch.<actor>` (compat binding `actors.<actor>.new.target`
  only). Outputs publish to `documents.ingest.<dtype>` with publisher confirms,
  mandatory routing, persistent delivery.
- ACK only after **every** required output document is confirmed; failure NACKs
  with a single bounded retry policy that does not poison-loop.
- Delivery is at-least-once ⇒ **deterministic document identity** is mandatory
  (see §5.3). Replayed targets must produce byte-identical documents (idempotent
  upsert downstream).
- Pika consumer thread owns settlement; Pykka actors own execution; probe
  effects run in worker threads / asyncio bridged off the mailbox (never the
  actor runtime).
- `ActorServiceRegistration` registry + conformance test (every runnable family
  registered, covered by Docker/compose — mirror
  `python/tests/test_container_coverage.py`).

### 4.2 Dual-form runner (the invariant, mechanically enforced)

`runner.py` exposes one entrypoint per actor operation:

```python
def run_operation(actor_id: str, operation: str, target: TargetSpec,
                  options: Mapping[str, Any]) -> list[JsonObject]
```

- Daemon path: transport decodes a dispatched target doc → builds `TargetSpec`
  → `run_operation` → transport validates + publishes + ACKs.
- CLI path: `starnet <actor> <subcommand> [target...] [--options...]` builds the
  **same** `TargetSpec` from argv/env → `run_operation` → the **same** validate +
  publish code path (`--rabbit-url` required-by-default, honoring
  `RABBITMQ_*` env; `--jsonl PATH` local-first fallback mirroring
  auto-dig receipts, but RabbitMQ publishing is the primary CLI contract).
- A conformance test (part of NET-001, run for every family) proves: for a
  recorded fake-probe session, daemon-form and CLI-form emit **byte-identical**
  document lists through the same publisher fake. This test is the gate for the
  operator's mandatory invariant.

### 4.3 Target shapes consumed

Input target docs (`dtype: target` dispatched by star-server, or CLI argv):

- `host` target: `{host: "10.0.0.5"}` or `{host: "dc01.corp.example"}` (a host
  doc `_id` may also be referenced via `target_id`).
- `cidr` target: `{cidr: "10.0.5.0/24"}` — consumed by `host-targets` router
  only; probe actors do not accept CIDRs directly (except `dns-recon
  reverse-sweep` which takes an explicit bounded CIDR option with hard caps).
- `domain` target: `{domain: "corp.example"}` for `dns-recon` and
  `ad-ldap-recon`.
- Per-actor `target_options` are declared in the manifest and validated against
  the manifest `configuration_schema` before probing.

## 5. Shared probe infrastructure (`starintel_network/probes/`)

### 5.1 Politeness / rate limiting

- Token bucket per destination host **and** per actor: default
  `1 request/second`, burst 2, jitter 10–250 ms. Global per-actor ceiling
  (default 4 concurrent in-flight probes fleet-wide).
- Per-target wall-clock budget default **60 s**; per-target probe-attempt cap
  (default 25 protocol exchanges). Exceeding a budget ends the run and emits an
  `observation` (`status: "budget-exhausted"`) — never a crash.
- Sweep caps: reverse sweep default max `/24`, hard max `/20` with explicit
  `--allow-large-sweep` flag; fan-out router caps in §6.11.
- All timeouts default 5 s connect / 10 s read; 2 retries max with 0.5 s
  backoff; rate-limit and auth-failure responses are terminal (no retry).

### 5.2 Evidence provenance rules (cross-cutting, mandatory)

- Every emitted document's `sources` array cites at least one `source` doc.
- A `source` doc records: `probe` (`<actor>.<operation>`), `target`,
  `request_summary` (method/opcode only — never credentials or full wire bytes),
  `response_bytes_sha256`, `response_size`, `captured_at` (UTC ISO), `tool` and
  `tool_version` (exact library versions: impacket/smbprotocol/ldap3/dnspython).
- One `observation` doc per probe attempt (success, refusal, timeout,
  auth-required) — negative results are findings (closed port = host liveness
  boundary data).
- `host.first_seen` / `host.last_seen` / `host.observed_by_ids` maintained by
  the host-doc builder from these observations.

### 5.3 Deterministic identity (dedupe under at-least-once)

- `host`: `starintel:host:<dataset>:<slug>` where slug is the lowercased
  canonical host key (ip-literal, else fqdn).
- `network-device`: `starintel:network-device:<dataset>:<slug>`.
- `relation`: `starintel:relation:<dataset>:<sha256>` over the canonical string
  `subject_id|predicate|object_id` (with endpoint objects serialized
  deterministically, sorted keys).
- `observation`: `starintel:observation:<dataset>:<sha256>` over
  `probe|target|ts_bucket(1h)|response_bytes_sha256`.
- `source`: `starintel:source:<dataset>:<sha256>` over
  `probe|target|response_bytes_sha256`.
- Upserts bump `version` + `date_updated`; replays never fork new ids.

### 5.4 `docs/` builders

Typed builders (pure functions, fully unit-tested): `build_host`,
`merge_host_enrichment` (set-only semantics — an actor may add
`service_records` entries and `os` fields, never delete another actor's),
`build_relation(subject_endpoint, predicate, object_endpoint)`,
`build_observation`, `build_source`. Relation endpoints are endpoint objects
per 0.10.1 (`{kind: host|ip|fqdn|service|domain|user, ...identity}`), and the
builder resolves endpoint → `_id` when the referenced doc exists/is emitted in
the same batch.

---

## 6. Actor catalogue

Legend for each actor: **Trigger** = accepted target shapes; **Ops limits** =
manifest-declared defaults (overridable per target via `target_options`);
**Outputs** = dtypes + concrete fields.

### 6.1 smb-recon

- **Purpose:** SMB null-session + guest enumeration — shares, sessions,
  logged-on users, domain info; the workhorse Windows fingerprinter
  (enum4linux-ng logic reimplemented, not shelled out).
- **Backing:** `smbprotocol` (SMB2/3 negotiate + anonymous session setup,
  share enumeration over SMB2), `impacket` (`impacket.smbconnection` for
  SMB1 negotiate fallback; `impacket.dcerpc.v5.samr/lsad/wkssvc/srvsvc` over
  the null session for NetShareEnumAll / NetSessionEnum / NetWkstaUserEnum /
  LSA QueryInfoPolicy2 domain+SID).
- **Probes (operations):** `negotiate` (TCP 445 SMB2 NEGOTIATE; capture dialect
  rev, signing-required, capabilities; SMB1 fallback only if
  `--allow-smb1`), `null-session` (anonymous SessionSetup; record
  success/guest/denied), `shares` (NetShareEnumAll / SMB2 share enum),
  `sessions` (NetSessionEnum + NetWkstaUserEnum), `domain-info`
  (LSA policy: domain NetBIOS name, domain SID, DC name).
- **Trigger:** host target. **Ops limits:** budget 60 s; max 25 exchanges;
  ops `shares|sessions|domain-info` gated on null-session success; one TCP
  connection reused for the whole operation set.
- **Outputs:**
  - `host.service_records` += `{port: 445, proto: "tcp", product:
    "Windows SMB", version: "SMB <dialect>"}`; `host.os` from SMB1
    `native_os`/`native_lm` when SMB1 negotiate is allowed (else defer OS to
    ntlm-fingerprint/ad-ldap-recon); `host.data.{netbios_domain,
    domain_sid}` from LSA.
  - `relation`: `member_of` host→domain endpoint (from LSA domain info);
    `communicates_with` client-host→target-host endpoints (from
    NetSessionEnum client list; client recorded as endpoint `{kind: host|ip}`).
  - `observation`: per-op results incl. share name lists (names, types,
    remarks), logged-on user names (names only).
  - `source`: per §5.2 for each exchange.
- **CLI form:** `starnet smb negotiate|null-session|shares|sessions|
  domain-info <host> [--allow-smb1] [--jsonl PATH] [--rabbit-url URL]`.
- **Opsec:** null/guest only; **no authenticated session setup, no lockout
  surface**; no tree connect with write access intents; never attempts share
  mount (mounting is share-scraper's read-only listing, which itself never
  opens file contents).
- **Test approach:** tests embed scripted SMB2 responders: a bytes-level fake
  speaking enough SMB2 (negotiate response, session-setup guest-OK/challenge,
  share-enum response) built from `smbprotocol`'s own codec expectations;
  impacket path tested against `impacket.smbserver.SimpleSMBServer` with null
  sessions enabled (hermetic, localhost-only ports). Replayed-response fakes
  make document output assertions deterministic.
- **Acceptance:** enumerates shares/sessions/domain against fakes; emits
  schema-valid docs with deterministic ids; opsec gate test fails the run if
  any authenticated session setup is attempted; dual-form conformance green.
- **Depends on:** SMB shared client lib slice (§ slice NET-004).

### 6.2 ad-ldap-recon

- **Purpose:** Active Directory via LDAP: rootDSE, naming contexts,
  users/groups/computers/SPNs with pagination.
- **Backing:** `ldap3` ( anonymous bind, simple bind only through the
  `CredentialProviderPort` seam, `ldap3.extend.standard.paged_search`
  paged control, `ldap3.utils.conv` for SID/UUID decoding).
- **Probes:** `rootdse` (anonymous read of rootDSE: namingContexts,
  defaultNamingContext, rootDomainNamingContext, supportedCapabilities,
  supportedControl, supportedSASLMechanisms, domainFunctionality —
  works unauthenticated against default AD); `enumerate` (paged searches
  under defaultNamingContext for `objectClass=user/group/computer`,
  SPN attribute `servicePrincipalName`, member/memberOf expansion — **requires
  an approved bind; v1 ships the port + fakes only, live bind activation is a
  separate future slice**).
- **Trigger:** host (DC) or domain target. **Ops limits:** page size 500,
  max 5000 entries/object-class, budget 120 s.
- **Outputs:**
  - `host` per computer object: `os.{name, version}` from
    `operatingSystem`/`operatingSystemVersion`; `device_class` ∈
    {`server`, `workstation`, `domain-controller`} (DC via
    `userAccountControl` SERVER_TRUST_ACCOUNT / primaryGroupID 521,
    workstation vs server via `userAccountControl` WORKSTATION_TRUST_ACCOUNT);
    `service_records` from SPNs (service-class + port when parseable, e.g.
    `MSSQLSvc/dc01.corp.example:1433` → `{port:1433, proto:"tcp", product:
    "MSSQL"}`); `data.{distinguished_name, sam_account_name}`.
  - `relation`: `member_of` computer→domain, user→group (authed mode);
    `hosted_on` service-endpoint→host for each SPN (when the SPN resolves to a
    known host); `employed_by` person→org only if person/org dtypes already
    exist downstream (emitted only in authed mode when `mail`/`manager`
    attributes map; v1 emits none by default).
  - `observation`: rootDSE capability record; anonymous-allowed/denied verdict;
    enumeration summaries (counts, not full dumps).
  - `source`: per §5.2 (search base + filter in `request_summary`, result
    bytes hash).
- **CLI form:** `starnet ad-ldap rootdse|enumerate <dc-or-domain>
  [--page-size N]`.
- **Opsec:** anonymous bind performs exactly one search (rootDSE) and nothing
  else; simple binds only via `CredentialProviderPort` (unimplemented in v1);
  no LDAP writes ever; result-size caps prevent unintentional full-domain
  dumps without an explicit `--max-entries` raise.
- **Test approach:** in-process LDAP server (`ldaptor`) serving a fixture DIT
  (2 DCs, 3 computers with OS attrs, groups, SPNs); anonymous-deny fake for
  the refuse path; paged-search page-boundary fixtures.
- **Acceptance:** rootDSE works anonymous; enumeration path proven against
  ldaptor with a fake credential provider; schema-valid outputs; no live
  authenticated mode without the future approved slice.
- **Depends on:** NET-002; feeds the NET-014 SPN→kerberos chain.

### 6.3 kerberos-recon

- **Purpose:** KDC user enumeration (AS-REQ without preauth →
  `PRINCIPAL_UNKNOWN` vs `PREAUTH_REQUIRED` oracle) and SPN scan; captures
  etypes for crypto posture.
- **Backing:** `impacket.krb5` (asn1 codecs, `krberror` parsing; client
  assembly following `impacket/examples/GetNPUsers.py` request shape — no
  preauth PA-ENC-TIMESTAMP is ever sent by default).
- **Probes:** `user-enum` (AS-REQ per candidate `user@REALM` **without** preauth
  PA; verdicts: `exists-preauth-required`, `exists-no-preauth` (NOPREAUTH is a
  notable finding, recorded as observation), `unknown`, `kdc-unreachable`);
  `spn-scan` (AS-REQ for `svc/fqdn@REALM` forms, input typically from
  ad-ldap-recon SPN lists or a CSV); `etype-probe` (from the KDC-ERR
  PA-ETYPE-INFO2: enctypes offered).
- **Trigger:** host (KDC) target + realm; or target referencing prior SPN
  observations. **Ops limits:** default rate 1 req/s (KDCs log aggressively),
  max 200 candidates/target run, budget 300 s.
- **Outputs:** `observation` per candidate verdict (username, verdict, etypes);
  `host.service_records` += `{port: 88, proto: "tcp", product: "Kerberos KDC"}`
  on the KDC host; `relation` `hosted_on` svc-endpoint→host for SPN hits with
  known hosts; `source` per exchange.
- **CLI form:** `starnet kerberos user-enum|spn-scan|etype-probe <kdc>
  --realm REALM [--candidates FILE]`.
- **Opsec:** **no preauth requests by default** (sends no encrypted timestamp ⇒
  does not increment failed-preauth counters); an explicit
  `--preauth-probe` flag exists but is disabled at build config level for
  this slice and documented as out-of-scope until the credential work; no
  ticket harvesting (no AS-REP encryption attempts).
- **Test approach:** scripted KDC fakes: raw TCP listeners returning canned
  KRB-ERROR blobs encoded via `impacket.krb5.asn1` (PREAUTH_REQUIRED,
  PRINCIPAL_UNKNOWN, NOPREAUTH, ETYPE-INFO2 variants); verdict-table tests.
- **Acceptance:** verdict mapping exact against fakes; rate limiter honored
  (observable via inter-arrival assertions on the fake); dual-form green.
- **Depends on:** NET-002.

### 6.4 dns-recon

- **Purpose:** Windows/AD DNS: zone transfer attempts, reverse sweeps, SRV
  records for AD services.
- **Backing:** `dnspython` (`dns.zone` AXFR client, `dns.resolver` with
  configurable NS, `dns.reversename` for PTR sweeps, `dns.rdatatype.SRV`).
- **Probes:** `axfr` (SOA→NS discovery for a domain, then AXFR attempt against
  each NS; success is recorded as a **finding** — observation
  `axfr-allowed`); `srv` (query `_ldap._tcp`, `_kerberos._tcp`,
  `_kerberos._udp`, `_gc._tcp`, `_kpasswd._tcp`, `_ldap._tcp.dc._msdcs`,
  `_ldap._tcp.pdc._msdcs`, plus configurable extra); `reverse-sweep`
  (bounded PTR sweep of a CIDR, caps per §5.1).
- **Trigger:** domain target (axfr/srv), host/cidr target (reverse-sweep).
- **Outputs:**
  - `relation` `resolves_to` name-endpoint→ip-endpoint for every A/AAAA/PTR
    hit; `hosted_on` zone-endpoint→NS-host for the served zone.
  - `host`: discovered A/PTR targets (device_class defaults `unknown` pending
    other actors); `host.service_records` on DC hosts from SRV targets
    (`_ldap._tcp`→`{port:389, proto:"tcp", product:"LDAP"}`,
    `_kerberos._tcp`→`{port:88, product:"Kerberos"}`, `_gc._tcp`→
    `{port:3268, product:"AD Global Catalog"}`, `_kpasswd._tcp`→
    `{port:464, product:"kpasswd"}`); `data.{dns_zone}` on the NS host.
  - `observation`: axfr verdicts per NS, SRV answer sets, sweep summaries.
  - `source`: per query (`request_summary` = qname/qtype; response hash).
- **CLI form:** `starnet dns axfr|srv|reverse-sweep <domain|cidr>
  [--resolver IP] [--extra-srv NAME]`.
- **Opsec:** AXFR is a standard read op; sweep caps enforced; resolver default
  is the target's own NS (avoids third-party resolver data pollution); one
  query/second/NS default.
- **Test approach:** in-process DNS server with `dnslib` serving canned zones
  (axfr-allowed, axfr-refused, SRV sets, PTR ranges); sweep-cap unit tests.
- **Acceptance:** axfr-allowed path yields resolves_to relations + source hash;
  SRV→service_records mapping exact; caps un-bypassable.
- **Depends on:** NET-002.

### 6.5 netbios-recon

- **Purpose:** nbtstat-style NBNS Node Status (UDP 137) name table +
  workgroup/domain leak. Deliberately the **first actor implemented** —
  simplest protocol, proves the whole fleet pattern end-to-end.
- **Backing:** `impacket.nmb` (NetBIOS name service codec + Node Status
  request) behind a small pure-python port so tests can fake at the codec
  boundary.
- **Probes:** `node-status` (send Node Status REQUEST to UDP 137, parse name
  table: unique names `<00>` workstation, `<03>` messenger, `<20>` file
  server, group names `<1C>` domain controllers, `<1B>` domain master
  browser; parse the trailing MAC address).
- **Trigger:** host target (IP required for broadcast-avoidance — unicast
  only).
- **Outputs:** `host.data.{netbios_name, netbios_names[], netbios_scope}`;
  `host.device_class` heuristic (`file-server` if `<20>` present, else
  `workstation`; `domain-controller` if `<1C>` member with `<1B>`); host
  `interface_records` += `{mac}` from the response trailer; `host.
  service_records` += `{port:137, proto:"udp", product:"NetBIOS NS"}`;
  `relation` `member_of` host→workgroup/domain endpoint; `observation`
  (full name table); `source`.
- **CLI form:** `starnet netbios node-status <ip>`.
- **Opsec:** single UDP probe (2 retries max), unicast only, no NBNS broadcast
  storms.
- **Test approach:** scripted UDP responder fakes returning recorded Node
  Status frames (workstation, DC, file server, empty); timeout path via
  blackhole fake.
- **Acceptance:** name-table parse matrix green; produces the full doc set
  (host+relation+observation+source) — this slice doubles as the reference
  implementation of the fleet pattern for the remaining actors.
- **Depends on:** NET-002.

### 6.6 winrm-probe

- **Purpose:** port 5985/5986 banner + auth negotiation fingerprint.
- **Backing:** `httpx` (plain + TLS with certificate verification disabled for
  fingerprint-only — recorded in source as `tls_verify:false`), NTLM Type-1
  construction via `impacket.ntlm` (decode of Type-2 challenge).
- **Probes:** `probe` (GET/POST `/wsman` expecting 401; then POST with
  `Authorization: Negotiate <base64 type1>`; parse `WWW-Authenticate:
  Negotiate <type2>` or `Basic realm`); records auth mechanisms offered
  (Negotiate/NTLM/Kerberos/Basic), product banner (Server header,
  `Microsoft-HTTPAPI/2.0`), TLS cert subject/issuer on 5986.
- **Trigger:** host target. **Ops limits:** 5 exchanges max.
- **Outputs:** `host.service_records` += `{port: 5985|5986, proto: "tcp",
  product: "WinRM" (or "Microsoft HTTPAPI"), version, auth: [mechanisms]}`;
  Type-2 parse feeds **ntlm-fingerprint's** shared parser inline (domain,
  computer names, NTLM version) → `host.data.{netbios_domain, dns_domain,
  fqdn}` + `host.os` + `relation member_of` host→domain; TLS cert →
  `host.data.{tls_cert_subject, tls_cert_issuer}` on the service record;
  `observation`; `source`.
- **CLI form:** `starnet winrm probe <host> [--ports 5985,5986]`.
- **Opsec:** never sends credentials — the Type-1 negotiate carries no secret;
  single probe pair per port.
- **Test approach:** `httpx` ASGI/real-socket fakes returning canned 401 +
  Type-2 sequences (Negotiate, Basic-only, connection-refused); TLS fake with
  self-signed cert fixture.
- **Acceptance:** auth-mechanism matrix; shared NTLM-parse parity tests with
  ntlm-fingerprint.
- **Depends on:** NET-002.

### 6.7 msrpc-probe

- **Purpose:** RPC endpoint mapper enumeration (TCP 135): UUID→service list;
  role inference for the host (DC, member server, print server).
- **Backing:** `impacket.dcerpc.v5.epm` (ept_lookup) + `impacket.dcerpc.v5.
  transport` (ncacn_ip_tcp primary; ncacn_np via the shared SMB lib when 135
  filtered but 445 open — optional).
- **Probes:** `epm` (bind EPM, insert+lookup towers until exhausted; collect
  `{uuid, version, annotation, protocol, endpoint}`); known-UUID map table
  (in-repo `msrpc_uuids.py`: EPM, RPCMGMT, LSARPC, SAMR, WKSSVC, SRVSVC,
  ATSVC, EventLog, SpoolSS, DRSUAPI, WMI, DHCP-Server, DNSR, IObjectExporter)
  → roles.
- **Trigger:** host target. **Ops limits:** max 200 towers, budget 60 s.
- **Outputs:** `host.service_records` += per TCP interface
  `{port: <epm-tcp-port>, proto: "tcp", product: "MSRPC <annotation>",
  version: "<uuid>/<if-version>"}` plus `{port:135, product:"RPC Endpoint
  Mapper"}`; `host.device_class` = `domain-controller` if DRSUAPI/DNSR
  present, `print-server` if SpoolSS-only, else `server`; `relation`
  `managed_by` member-host→dc-endpoint when DRSUAPI is observed **and** a DC
  endpoint is resolvable from prior docs (else defer — relation emitted only
  with a resolvable object); `observation` (interface map); `source`.
- **CLI form:** `starnet msrpc epm <host> [--via-smb]`.
- **Opsec:** EPM read-only; no interface **binds** beyond EPM itself (UUID
  list comes from the mapper, not from probing each interface).
- **Test approach:** bytes-level EPM fake speaking impacket's DCERPC codec
  (bind-ack + canned tower entries); UUID-map table unit tests.
- **Acceptance:** tower enumeration exact against fake; role inference matrix;
  `managed_by` emitted only with resolvable object (negative test).
- **Depends on:** NET-004 (ncacn_np path shares the SMB lib).

### 6.8 ntlm-fingerprint

- **Purpose:** extract identity/OS telemetry from NTLM challenges over SMB
  and HTTP — the highest-signal unauthenticated Windows fingerprint.
- **Backing:** shared `smbprotocol`/impacket session-setup failure path (SMB
  anonymous setup that yields a Type-2 challenge when null sessions are
  disabled — the challenge **is** the product), `httpx` for HTTP NTLM
  (IIS/Exchange/ADFS URLs supplied by the target), `impacket.ntlm` for
  Type-1/Type-2 codecs (or `smbprotocol`'s NTLM structs — one parser,
  shared with winrm-probe in `probes/ntlm_parse.py`; no duplicate decoder).
- **Probes:** `smb-challenge` (445 anonymous session setup → capture Type-2);
  `http-challenge` (target-supplied URL, one GET → 401 Negotiate → Type-2).
  Parse: `NTLMv{1,2}`, NetBIOS domain, NetBIOS computer name, DNS domain,
  DNS computer name (AV pairs `MsvAvNbDomainName`, `MsvAvDnsComputerName`,
  `MsvAvDnsDomainName`, `MsvAvNbComputerName`), NTLM version field →
  Windows build map (in-repo table: `10.0 build 20348`→`Windows Server
  2022`, `10.0 19041`→`Windows 10 2004/Server 2004`+, `6.3`→`8.1/2012R2`,
  ...), challenge flags (signing, seal, target-info).
- **Trigger:** host target (`smb-challenge`), host+url target
  (`http-challenge`).
- **Outputs:** `host.os` = `{name: "Windows", version: <build>,
  build: <ntlm-build>, fingerprint_source: "ntlm"}`; `host.data.{netbios_
  domain, netbios_computer_name, dns_domain, fqdn, ntlm_version,
  smb_signing_required}`; `relation member_of` host→domain endpoint;
  `host.service_records` += on the probed port `{product: "NTLM over
  SMB|HTTP"}`; `observation`; `source` (challenge bytes hash).
- **CLI form:** `starnet ntlm smb-challenge <host> | http-challenge
  <host> --url URL`.
- **Opsec:** sends only anonymous/Type-1 traffic; one exchange per surface.
- **Test approach:** Type-2 blob corpus fixtures (recorded challenges across
  Windows versions) → parser + build-map table tests; SMB fake from the
  shared SMB lib harness returns challenge-on-anonymous.
- **Acceptance:** build-map coverage for every NTLM version field value in the
  corpus; parity: smb/http/winrm probes share one parser module (structural
  test forbids a second NTLM decoder).
- **Depends on:** NET-004.

### 6.9 share-scraper (optional but scoped)

- **Purpose:** bounded, read-only listing of readable shares — names and
  aggregate sizes only. **No content download — hard, tested rule.**
- **Backing:** the shared SMB client lib (`smbprotocol` tree connect +
  query-directory; sizes via `FileStandardInformation` on directories only —
  no file opens for read).
- **Probes:** `list-shares` (given smb-recon's share observations or a fresh
  null-session enum: for each candidate share, tree-connect read-only; if
  accessible: list to depth ≤ 2, ≤ 500 entries/share, record per-share
  `{name, type, entry_count, total_bytes_aggregate, largest_file_bytes}`).
- **Trigger:** host target. **Ops limits:** max 20 shares, depth 2, 500
  entries/share, budget 300 s; **the client adapter API exposes no read-file
  operation at all** (structural test: no `read`/`openfile`-content method
  exists on the port).
- **Outputs:** `observation` per share summary (never entry-level names
  beyond top-level directories — top-level names only, no recursive name
  dump); `host.service_records` += `{port:445, product:"SMB shares
  readable", version: <share count>}`; `source` per listing (response hash).
- **CLI form:** `starnet share-scraper list-shares <host> [--max-shares N]`.
- **Opsec:** data minimization by construction; no file handles opened for
  content; audit log line per tree-connect.
- **Test approach:** SMB fake exposing IPC$ (deny), readable share with N
  entries; negative structural test for absence of content-read API;
  entry-cap and depth-cap tests.
- **Acceptance:** summary-only observations; caps enforced; structural
  no-download test green.
- **Depends on:** NET-005 (smb-recon) for the share-observation input shape.

### 6.10 host-targets (router)

- **Purpose:** fan-out `cidr`/range targets into per-host targets for the
  probe actors — the network analogue of pro-actors' `username-targets`.
- **Backing:** Pykka + the shared transport; `ipaddress` stdlib for expansion.
- **Operations:** `fan-out` (expand CIDR — skip network/broadcast/multicast;
  emit `target` docs routed to `documents.target.dispatch.<probe>` for each
  actor in `target_options.probes` (default set: netbios, smb, msrpc,
  winrm, ntlm)); hard rate ceiling `max_hosts_per_second` (default 10).
- **Outputs:** `target` docs only (+ `observation` summary of fan-out). Caps:
  default max `/24` expansion, `/20` hard max without explicit
  `--allow-large-sweep`.
- **CLI form:** `starnet host-targets fan-out <cidr> [--probes a,b]
  [--max-rate N]`.
- **Test approach:** expansion unit tests (boundary skip, caps), fake broker
  asserting routing keys and inter-arrival rate.
- **Acceptance:** rate ceiling observable; caps unbypassable; emits nothing
  but targets+observation.
- **Depends on:** NET-002.

### 6.11 Integration chain (slice NET-014)

ad-ldap-recon SPN observations → dispatch kerberos-recon `spn-scan` targets
against the realm's KDCs (discovered via dns-recon `_kerberos._tcp` SRV);
kerberos SPN hits → `hosted_on` relations joining to hosts minted by
dns/ldap. This is runtime composition via published documents — no actor
imports another; the chain lives in `host-targets`-style routing options and
an integration test that runs three families against fakes in sequence,
asserting the joined relation set.

## 7. Actor → 0.10.1 dtype field mapping (summary — full table in dtype-mapping.md)

| actor | host fields | relations (predicate) | observation | source |
|---|---|---|---|---|
| smb-recon | service_records[445], os (SMB1 only), data.netbios_domain/domain_sid | member_of, communicates_with | shares/sessions/domain ops | per exchange |
| ad-ldap-recon | os (LDAP attrs), device_class, service_records[SPNs], data.dn/sam | member_of, hosted_on | rootDSE/enumeration | per search |
| kerberos-recon | service_records[88] on KDC | hosted_on (SPN hits) | user-enum verdicts, etypes | per AS-REQ |
| dns-recon | new hosts, service_records[389/88/3268/464/53] | resolves_to, hosted_on (zone→NS) | axfr verdicts, SRV, sweeps | per query |
| netbios-recon | data.netbios_*, device_class, interface_records[mac], service_records[137/udp] | member_of | name table | per probe |
| winrm-probe | service_records[5985/5986], os via NTLM, data.tls_cert_* | member_of (via NTLM) | auth mechanisms | per probe |
| msrpc-probe | service_records[135 + towers], device_class | managed_by (host→DC) | interface map | per EPM call |
| ntlm-fingerprint | os{build}, data.{domains,fqdn,ntlm_version} | member_of | challenge summary | per challenge |
| share-scraper | service_records[445 sizes] | — | share summaries | per listing |
| host-targets | — | — | fan-out summary | — |

## 8. Scheduling and limits (cross-cutting)

- Daemon actors are idle until dispatched targets arrive; no autonomous
  background scanning in v1. Fleet scheduling = operator/server-side target
  issuance.
- Per-actor config schema (manifest `configuration_schema`) exposes: rate,
  concurrency, timeout, budget, and per-actor caps from §6; all have
  manifest-declared defaults and hard maximums (validated at target decode;
  oversize options NACK permanently with a contract error).
- Compose profiles: `fleet` (all daemons), `batch` (CLI one-shots),
  `router` (host-targets).

## 9. Auth handling (cross-cutting)

- v1 is **unauthenticated-only**. Every actor's default surface performs no
  credential-bearing exchange. The only seams are:
  - `CredentialProviderPort` (ad-ldap-recon, future others): typed port,
    no implementation in this slice set; live implementation is explicitly
    deferred to separate approved work.
  - Kerberos `--preauth-probe`: flag exists, disabled at config level.
- No credential material ever enters documents, logs, `source.request_summary`,
  or fakes.

## 10. Test strategy (cross-cutting)

- Hermetic first: every protocol has an in-repo fake (scripted byte
  responders + recorded frames; SMB via `smbprotocol`-codec-aware fake and
  impacket `SimpleSMBServer`; LDAP via `ldaptor`; DNS via `dnslib`; NBNS/
  DCERPC/KDC via codec-built canned frames). No live-network tests in the
  default gate.
- Conformance: manifest registry vs structure, container coverage, and the
  **dual-form byte-identity** test per family.
- Determinism: recorded-response fixtures ⇒ golden document sets (ids stable
  across replays).
- Live lab (opt-in env `STARINTEL_NET_LIVE_TEST=1`): compose-provided
  Samba + BIND + KDC containers on an isolated network, per-run ports.
- Gates per pro-actors convention: `pytest`, `ruff check .`, `mypy` from
  `python/`, recorded via `prolog-verify observe`.

## 11. Slice plan summary

Infrastructure first, pattern-proving actor second, protocol actors, then
integration. Full issue bodies in `issue-slices.json`.

| id | title | depends_on |
|---|---|---|
| NET-001 | Bootstrap starintel-network: runtime, transport, dual-form runner, schema lock 0.10.x pin | — (blocked on canonical 0.10.1 mint) |
| NET-002 | Probe support library + protocol-fake test harness | NET-001 |
| NET-003 | netbios-recon actor (fleet pattern reference) | NET-002 |
| NET-004 | Shared SMB client library (`SmbTransportPort`) | NET-002 |
| NET-005 | smb-recon actor | NET-004 |
| NET-006 | ntlm-fingerprint actor (shared NTLM parser) | NET-004 |
| NET-007 | msrpc-probe actor (endpoint mapper) | NET-004 |
| NET-008 | dns-recon actor | NET-002 |
| NET-009 | winrm-probe actor | NET-002 |
| NET-010 | ad-ldap-recon actor (anonymous rootDSE + authed-path ports) | NET-002 |
| NET-011 | kerberos-recon actor (user-enum, SPN scan) | NET-002 |
| NET-012 | share-scraper actor (sizes-only, no content) | NET-005 |
| NET-013 | host-targets router (CIDR fan-out) | NET-002 |
| NET-014 | Fleet integration + ad-ldap→kerberos SPN enrichment chain | NET-003..NET-013 |
