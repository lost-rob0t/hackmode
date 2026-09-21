%% hackmode_actor_ontology.pl — design decisions for the hackmode starintel
%% actor system, encoded as queryable relations. This is the expert KB the
%% implementation must satisfy; tests cross-check the compiled star-lang
%% ontology and CL runtime against these facts.

:- module(hackmode_actor_ontology, [ontology_library/2, document/3, predicate_/3, message/1, message_field/4, actor/5, invariant/1, projectable/2, requires/2, consumes/2, evidence_path/1]).

%% Ontology identity: hackmode library imports the canonical starintel core.
ontology_library('dev.hackmode/core@1', 'spec/hackmode-core.star').
ontology_imports('org.starintel/core@1', 'spec/vendor/starintel-core-0.10.1.star',
                 'sha256:0c6a50a12a9779a0e760cd48d6e4f3bf3fdadf04e61ec3cb67f8685fe64499a5').

%% document(Name, Persistence, ProjectsTo).
%% ProjectsTo is a 0.10.1 dtype atom, local_only, or runtime_state.
document(hackmode-document, persistent, base).
document(operation,       persistent, operation).
document(domain,          persistent, domain).
document(host,            persistent, host).
document(url,             persistent, url).
document(port,            persistent, local_only).        %% 0.10.1 has no port dtype
document(finding,         persistent, local_only).        %% future: observation/analysis
document(http-exchange,   persistent, http-transaction).  %% lossless headers retained
document(visual-evidence, persistent, web-capture).
document(research-node,   persistent, research-node).     %% expert objective state
document(capture-session, transient,   runtime_state).
document(provider-job,    transient,   runtime_state).
document(outbox-entry,    transient,   runtime_state).

%% predicate_(Name, Source, Destination) — ontology relations.
predicate_(resolves-to,    domain, host).
predicate_(hosted-on,      port, host).
predicate_(serves-url,     host, url).
predicate_(discovered-in,  hackmode-document, operation).
predicate_(observed-in,    http-exchange, operation).
predicate_(evidence-of,    http-exchange, hackmode-document).
predicate_(evidence-of,    visual-evidence, hackmode-document).
predicate_(produced-by,    hackmode-document, provider-job).

%% message(Name) + message_field(Name, Field, Type, Required).
:- discontiguous message/1, message_field/4.
message(discover-asset).
message_field(discover-asset, asset, reference, required).
message(asset-discovered).
message_field(asset-discovered, assetId, string, required).
message_field(asset-discovered, kind, string, required).
message(run-capability).
message_field(run-capability, capability, string, required).
message_field(run-capability, input, map, required).
message(provider-result).
message_field(provider-result, jobId, string, required).
message_field(provider-result, status, string, required).
message_field(provider-result, assets, list_of_reference, required).
message(enqueue-document).
message_field(enqueue-document, json, string, required).
message_field(enqueue-document, dtype, string, required).
message(drain-outbox).
message(outbox-state).
message_field(outbox-state, queued, integer, required).
message_field(outbox-state, failed, integer, required).
message(start-capture).
message_field(start-capture, spec, map, required).
message(stop-capture).
message(capture-state).
message(replay-spool).
message_field(replay-spool, spoolPath, string, required).
message_field(replay-spool, operationId, string, required).
message_field(replay-spool, captureSessionId, string, required).
message_field(replay-spool, sourceId, string, required).
message(classify-target).
message_field(classify-target, target, string, required).
message(recommend-capabilities).
message_field(recommend-capabilities, target, string, required).
message(expert-recommendation).
message_field(expert-recommendation, capability, string, required).
message_field(expert-recommendation, reason, string, optional).

%% actor(Name, File, Accepts, Produces, Role).
actor(asset-monitor,       'spec/actors/asset-monitor.star',
      [asset-discovered],                    [enqueue-document], project_assets).
actor(outbox,              'spec/actors/outbox.star',
      [enqueue-document, drain-outbox],      [outbox-state],     ingest_starintel).
actor(provider-dispatcher, 'spec/actors/provider-dispatcher.star',
      [run-capability],                      [provider-result, asset-discovered], run_capabilities).
actor(capture-supervisor,  'spec/actors/capture-supervisor.star',
      [start-capture, stop-capture],         [capture-state],    manage_ipx_capture).
actor(replay,              'spec/actors/replay.star',
      [replay-spool],                        [enqueue-document], fold_spool_evidence).
actor(expert-advisor,      'spec/actors/expert-advisor.star',
      [classify-target, recommend-capabilities], [expert-recommendation], advisory_reasoning).

%% Invariants the implementation must uphold.
invariant(lossless_evidence).        %% http-exchange keeps exact observed headers
invariant(advisory_expert).          %% expert actor never mutates; producers are CL effects
invariant(projection_from_authority).%% emitted schema_version must equal starintel_spec:emitted_schema_version
invariant(one_starintel_schema).     %% no second document schema; 0.10.1 envelope only at the projection boundary

%% --- Expert rules ----------------------------------------------------------

%% Which documents can be projected to starintel 0.10.1 today?
projectable(Document, Dtype) :-
    document(Document, persistent, Dtype),
    Dtype \= base, Dtype \= local_only, Dtype \= runtime_state.

%% Projection completeness rule: every projectable document must satisfy the
%% dtype's required data fields in the projection layer.
requires(Dtype, Fields) :- starintel_spec:dtype_data_required(Dtype, Fields).

%% Wire routing rule: which actor consumes a message?
consumes(Actor, Message) :- actor(Actor, _, Accepts, _, _), member(Message, Accepts).

%% Evidence rule: evidence documents flow to starintel through the outbox actor
%% only; no actor posts directly to starintel-server.
evidence_path(Doc) :- member(Doc, [http-exchange, visual-evidence]),
                      consumes(outbox, enqueue-document).
