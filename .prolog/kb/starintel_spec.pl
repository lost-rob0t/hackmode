%% starintel_spec.pl — StarIntel spec authority facts (verified 2026-09-20).
%%
%% Authority chain (how to re-resolve, never trust memory):
%%   1. Consumer lock: schema/starintel-schema.lock.json in any starintel-server-class repo.
%%   2. Canonical repo: lost-rob0t/starintel-gpt-auto-dig (schemas/ + starintel_doc/spec.py).
%%   3. git ls-remote over SSH (https remotes abort on this host).
%% Verified from canonical main 64c101af3ca8207aed976583060e33152371c3d4 (PR #2735 era).

:- module(starintel_spec, []).

%% release(Release, SchemaVersion, Profile) — active release is 0.10.1.
release('0.10.1', '0.10.1', 'starintel-core').
superseded_by('0.9.1', '0.10.1').
superseded_by('0.9.2', '0.10.1').          % 0.9.2 network-capture profile folded into core
canonical_repository('lost-rob0t/starintel-gpt-auto-dig').
canonical_commit_main('64c101af3ca8207aed976583060e33152371c3d4').
schema_revision('0.10.1+fields.20260919.1').
migration_window_accepts(['0.9.0', '0.10.1']).
emitted_schema_version('0.10.1').

%% Envelope (top-level required fields, JSON Schema authority).
envelope_required(['_id', dataset, dtype, schema_version, version,
                   date_added, date_updated, sources, evidence, data]).
%% data payload fields are snake_case; data.additionalProperties = false.
data_key_style(snake_case).

%% dtype(+) facts: the 58 dtypes of 0.10.1.
dtype(D) :- member(D, [actor-manifest, address, alert, analysis, asset, breach,
                       campaign-finance, claim, concept, contract, dataset-manifest,
                       document, domain, education, email, email-message, employment,
                       entity, event, evidence-record, file, financial-observation,
                       geo, grant, host, http-transaction, investigation-target,
                       legal-case, lobbying-filing, location, media, meeting, message,
                       network, network-conversation, network-device, observation,
                       operation, org, ownership, pcap-capture, person, phone, policy,
                       procurement, product, relation, research-node, research-pass,
                       social-media-post, source, target, task, url, user, web-capture,
                       wireless-network, wireless-station]).

%% dtype_data_required(Dtype, RequiredFields) — only dtypes with required data fields.
dtype_data_required(operation, [mission, status, phases]).
dtype_data_required(research-node, [objective, status]).
dtype_data_required(http-transaction, [transaction_id, method, url, response_status]).
dtype_data_required(web-capture, [capture_id, url, screenshot_uri, screenshot_hash]).
dtype_data_required(pcap-capture, [capture_id, file_uri, file_sha256]).
dtype_data_required(wireless-network, [bssid, security]).
dtype_data_required(wireless-station, [mac]).
dtype_data_required(investigation-target, [target]).
dtype_data_required(target, [target]).
dtype_data_required(domain, [domain]).
dtype_data_required(url, [url]).

%% Absent dtypes that older vocabularies assumed (star-lang fixture org.starintel/core@1
%% and hackmode v0.9 habits). Projecting these as dtypes is invalid on 0.10.1.
absent_dtype(finding).
absent_dtype(port).
absent_dtype(service).
absent_dtype(scope).
absent_dtype(asn).
absent_dtype(cert).
