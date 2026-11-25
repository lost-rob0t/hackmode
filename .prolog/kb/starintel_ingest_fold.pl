% Durable knowledge: StarIntel desktop-stack ingest fold (hackmode -> starintel-desktop).
% Verified live 2026-11-24 against the running starintel-desktop stack
% (star-server image starintel/server:0.1.0, branch pin fix/documents-list-route):
% canonical + legacy route probes, outbox drain e2e (quarantined then acknowledged),
% corpus bulk import. Evidence: workspace root run journal run-no-git.pl 2026-11-24 entries.

% --- route map (verified by live probes with a Bearer star_sk_v1 key) ---
ingest_route(legacy, 'POST /new/document/:dtype', documents_write).
ingest_route(legacy, 'GET /search', search_read).
ingest_route(legacy, 'POST /documents/bulk', documents_bulk).
ingest_route(contract, 'POST /api/v1/documents/bulk', documents_bulk).
ingest_route(dead, '/api/v0/*', unmapped_403_everyone).   % prefix not in route-action map
wire_note(bearer_only, 'Authorization: Bearer <star_sk_v1_...>; the key file is secrets/<user>_api_key in the desktop checkout; header probed OK on bare /search and /new/document/:dtype').

% --- schema acceptance (verified by POST probes) ---
wire_note(canonical_verbatim, 'canonical camelCase schemaVersion 0.10.1 documents (star-bbp corpus shape) are accepted VERBATIM on the same /new/document/:dtype route via the canonical-document-p path — no client-side projection needed').
wire_note(legacy_strict, 'legacy snake_case documents validate against pinned v0.9.0: requires _id, dataset, dtype, schema_version "0.9.0", version:int>=1, date_added/date_updated, sources[], evidence[] (confidence is a NUMBER), data per dtype (domain needs data.domain)').
wire_note(violation_detail, 'violations return 422 invalid_document_schema with info.reason carrying a JSON pointer (e.g. $.provenance: undeclared_field operation) — read it for the exact fix').

% --- provenance contract (root cause of the 2026-11-24 quarantine) ---
provenance_contract(pinned_v090, additional_properties_false).
provenance_contract(allowed_keys, [actor, agent, collector, collector_type, created_by,
    environment, imported_from, metadata, method, model, notes, operation_id,
    original_id, original_path, original_schema_version, pipeline, prompt_hash,
    run_id, session_id, skill, software_version, tool, transform, updated_by]).
provenance_contract(rejected_keys, ['operation', 'producer']).  % star-cl projection emits these
projection_rule(provenance_map, 'map operation -> operation_id and producer -> tool before enqueue; user init ~/.config/hackmode/init.lisp wraps asset->starintel-json for this until the product fix (ADADR candidate: asset-starintel-provenance should emit schema-legal keys natively)').

% --- outbox behavior (verified by drain probes) ---
outbox_rule(quarantine_permanence, '4xx (except 408/425/429) marks the entry :quarantined with NO retry — a schema-drift projection silently strands docs in the local tek9 outbox; drain tooling must surface quarantined entries').
outbox_rule(ack_semantics, 'ACK = ingest-accepted (server validated + published to broker); does NOT claim CouchDB persistence completed').
outbox_rule(actor_timing, 'start-outbox-actor requires an open operation database; *db* opens on use-operation, so user config must hook that moment (fdefinition wrap of use-operation is the init.lisp pattern)').
outbox_rule(credential_hygiene, 'transport takes a headers-function called per request so credentials never persist in outbox records — keep that property in any wiring').

% --- desktop stack state after the 2026-11-24 session ---
desktop_import(dataset_cyber_recon, domain, 33968).
desktop_import(dataset_cyber_recon, url, 9742).
desktop_import(dataset_cyber_recon, source, 935).
desktop_import(skipped, oversize_source_docs, 3).   % each >1MB server body cap
desktop_import(excluded_targets, 78487, 'CI recon job definitions (actor star:v1:resolver:dns); importing would dispatch live recon through the desktop fleet — gated by bbp-lane-routing REV 1').
bulk_limits(server, 500, documents_per_request).
bulk_limits(server, 1048576, request_body_bytes).
bulk_note(async_202, 'large bulk batches return 202 accepted (async ingest job)').
