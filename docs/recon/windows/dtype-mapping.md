# Windows recon actor set → StarIntel 0.10.1 dtype field mapping

Companion to `design.md`. Every emitted field below is expressed against the
0.10.1 dtype set being minted in parallel: `host` (enriched), `network-device`,
`relation` (subject/predicate/object with endpoint objects), `observation`,
`source`.

**Fail-closed rule:** these field names are normative-from-operator-instruction
pending the canonical 0.10.1 mint. NET-001 pins the schema lock; each actor
slice reconciles this table against the minted schema + `starintel_doc`
validators and records any delta in its issue before merge. Minted schema wins.

Envelope rules for all documents: deterministic `_id` (design §5.3),
`schema_version` = locked base family, `sources[]` citing `source` docs,
`version`/`date_updated` upsert semantics, `dataset` from target doc.

## host (enriched)

Fields: `device_class` (enum), `interface_records`, `service_records`
({port, proto, product, version}), os fields, `first_seen`, `last_seen`,
`observed_by_ids`, plus `data.*` free enrichment keys named below.

| source actor + probe | field | value shape / example |
|---|---|---|
| smb-recon `negotiate` | `service_records[]` | `{port: 445, proto: "tcp", product: "Windows SMB", version: "SMB 3.1.1"}` |
| smb-recon `negotiate` (SMB1 only) | `os` | `{name: native_os, version: native_lm, fingerprint_source: "smb1"}` |
| smb-recon `domain-info` | `data.netbios_domain`, `data.domain_sid` | `"CORP"`, `"S-1-5-21-…"` |
| ad-ldap-recon `enumerate` (computers) | `os` | from `operatingSystem`/`operatingSystemVersion` |
| ad-ldap-recon `enumerate` | `device_class` | `domain-controller` / `server` / `workstation` (UAC bits + primaryGroupID 516/521) |
| ad-ldap-recon SPNs | `service_records[]` | e.g. `MSSQLSvc/dc01.corp.example:1433` → `{port: 1433, proto: "tcp", product: "MSSQL"}` |
| ad-ldap-recon | `data.distinguished_name`, `data.sam_account_name` | DN strings |
| kerberos-recon (any op) | `service_records[]` (on KDC host) | `{port: 88, proto: "tcp", product: "Kerberos KDC"}` |
| dns-recon `axfr`/`reverse-sweep` | new `host` docs (A/PTR hits) | `device_class: "unknown"` pending other actors |
| dns-recon `srv` | `service_records[]` (on DC hosts) | `_ldap._tcp`→`{port:389,proto:"tcp",product:"LDAP"}`; `_kerberos._tcp`→`{port:88,…,"Kerberos"}`; `_gc._tcp`→`{port:3268,…,"AD Global Catalog"}`; `_kpasswd._tcp`→`{port:464,…,"kpasswd"}` |
| dns-recon | `data.dns_zone` (on NS host) | zone name |
| netbios-recon `node-status` | `data.netbios_name`, `data.netbios_names[]`, `data.netbios_scope` | parsed name table |
| netbios-recon | `device_class` | `file-server` (`<20>`), `workstation`, `domain-controller` (`<1B>`+`<1C>`) |
| netbios-recon | `interface_records[]` | `{mac: "00:11:22:33:44:55"}` (Node Status trailer) |
| netbios-recon | `service_records[]` | `{port: 137, proto: "udp", product: "NetBIOS NS"}` |
| winrm-probe `probe` | `service_records[]` | `{port: 5985|5986, proto: "tcp", product: "WinRM"| "Microsoft HTTPAPI", version, auth: ["Negotiate","NTLM"]}` |
| winrm-probe (TLS) | service-record ext `data.tls_cert_subject`, `data.tls_cert_issuer` | cert identity strings |
| winrm-probe + ntlm-fingerprint (shared parse) | `os` | `{name: "Windows", version: mapped, build: ntlm-build, fingerprint_source: "ntlm"}` |
| winrm-probe + ntlm-fingerprint | `data.netbios_domain`, `data.netbios_computer_name`, `data.dns_domain`, `data.fqdn`, `data.ntlm_version` | AV-pair extraction |
| ntlm-fingerprint | `data.smb_signing_required` | bool from challenge flags |
| ntlm-fingerprint | `service_records[]` (on probed port) | `{port: 445|80, product: "NTLM over SMB"|"NTLM over HTTP"}` |
| msrpc-probe `epm` | `service_records[]` | `{port: 135, product: "RPC Endpoint Mapper"}` + per-tower `{port: <dyn>, proto: "tcp", product: "MSRPC <annotation>", version: "<uuid>/<ifver>"}` |
| msrpc-probe | `device_class` | `domain-controller` (DRSUAPI/DNSR), `print-server` (SpoolSS-only), `server` |
| share-scraper `list-shares` | `service_records[]` | `{port: 445, product: "SMB shares readable", version: "<share-count>"}` |
| all host-touching actors | `first_seen`, `last_seen`, `observed_by_ids` | maintained by `docs/merge_host_enrichment` from observations (set-only merges; no deletions) |

## network-device

| source actor | field | value |
|---|---|---|
| dns-recon (NS host serving a zone, when distinct infra identified) | network-device doc | `{data.role: "dns-server", data.dns_zone}` with `service_records[] {port:53, proto:"tcp/udp", product:"DNS"}` |
| msrpc/dns role inference on non-Windows-looking infra (banner≠Windows) | network-device fallback | only when host evidence shows non-Windows product (e.g. BIND banner); otherwise stay `host` |

## relation (subject/predicate/object with endpoint objects)

Predicates used: `communicates_with`, `connected_to`, `hosted_on`,
`member_of`, `resolves_to`, `managed_by` (+ `employed_by` reserved for the
future authed AD person/org work — v1 emits none).

| actor | predicate | subject endpoint | object endpoint | evidence source |
|---|---|---|---|---|
| smb-recon (LSA domain) | `member_of` | host | domain `{kind: domain, netbios, sid}` | smb `domain-info` |
| smb-recon (NetSessionEnum) | `communicates_with` | client host/ip | target host | smb `sessions` |
| ad-ldap-recon | `member_of` | computer host / user endpoint | domain / group endpoint | ldap `enumerate` |
| ad-ldap-recon SPNs | `hosted_on` | service `{kind: service, spn}` | host | ldap `enumerate` |
| kerberos-recon spn hits | `hosted_on` | service `{kind: service, spn}` | host | kerberos `spn-scan` |
| dns-recon A/AAAA/PTR | `resolves_to` | `{kind: fqdn}` | `{kind: ip}` | dns query |
| dns-recon zone→NS | `hosted_on` | `{kind: dns-zone, name}` | NS host | `axfr`/SOA-NS |
| netbios-recon | `member_of` | host | workgroup/domain `{kind: domain, netbios}` | NBNS name table |
| winrm/ntlm (AV pairs) | `member_of` | host | domain `{kind: domain, netbios/dns}` | NTLM Type-2 |
| msrpc-probe (DRSUAPI + resolvable DC) | `managed_by` | member host | DC host endpoint | EPM map |
| share-scraper | — (none) | — | — | — |
| host-targets | — (none) | — | — | — |

## observation

One per probe attempt (success/refusal/timeout/auth-required/budget-exhausted).
Payload keys per actor:

| actor | observation payload |
|---|---|
| smb-recon | `{op, share_names[] {name,type,remark}, session_clients[], logged_on_users[], null_session: allowed|guest|denied}` |
| ad-ldap-recon | `{op, anonymous: allowed|denied, rootdse {naming_contexts, capabilities, sasl_mechanisms, domain_functionality}, counts {users,groups,computers,spns}}` |
| kerberos-recon | `{op, verdict: exists-preauth-required|exists-no-preauth|unknown|kdc-unreachable, username, etypes[]}` |
| dns-recon | `{op, axfr: allowed|refused, srv_answers[], sweep_summary}` |
| netbios-recon | `{op, name_table[] {name, suffix, type: unique|group}}` |
| winrm-probe | `{op, port, auth_mechanisms[], server_banner}` |
| msrpc-probe | `{op, interfaces[] {uuid, version, annotation, proto, endpoint}}` |
| ntlm-fingerprint | `{op, surface: smb|http, ntlm_version, flags}` |
| share-scraper | `{op, share {name, entry_count, total_bytes, largest_file_bytes, top_level_names[]}}` (top level only) |
| host-targets | `{op, hosts_fanned, rate_limited}` |

## source

Per evidence rule (design §5.2) — every actor emits one `source` per probe
exchange with:

```json
{
  "data": {
    "probe": "<actor>.<operation>",
    "target": "<ip|fqdn|domain>",
    "request_summary": {"method|opcode|qname…": "…", "auth": "none"},
    "response_bytes_sha256": "…",
    "response_size": 1234,
    "captured_at": "2026-09-19T…Z",
    "tool": "impacket|smbprotocol|ldap3|dnspython|httpx",
    "tool_version": "<exact pinned version>"
  }
}
```

No credentials, no raw wire bytes, no file content ever appear in `source`
(or any other dtype).
