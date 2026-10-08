%% Star Language is the canonical StarIntel 0.10.1 authority.
:- module(starintel_spec, []).
release('0.10.1', '0.10.1', 'org.starintel/core@1').
canonical_repository('lost-rob0t/star-lang').
canonical_commit_main('fa1c8f4fb0590526c39aa3e9bc4a7e6eac30bea7').
canonical_source('specs/starintel/0.10.1/core.star').
consumer_lock('schema/starintel-schema.lock.json').
emitted_schema_version('0.10.1').
envelope_required([id, dataset, dtype, schemaVersion]).
data_key_style(lower_camel_case).
wire_shape(flat).
timestamp_type(unix_seconds).
projection_dtype(domain, [name]).
projection_dtype(host, [ip]).
projection_dtype(url, [url]).
projection_dtype(operation, [mission, status, phases]).
projection_dtype('research-node', [objective, status]).
projection_dtype('http-transaction', [transactionId, method, url, responseStatus]).
projection_dtype('web-capture', [captureId, url, screenshotUri, screenshotHash]).
reference_required([schema, id]).
phase_required([phaseId, objective, state]).
canonical_dtype(port).
canonical_dtype(finding).
absent_dtype(cert).
