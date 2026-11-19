%% logicStrike bridge — snapshot assets -> technique candidates.
%%
%% Classification keys ONLY on the CL-owned asset-kind vocabulary
%% ("domain", "host", "url", ...). Snapshot values are opaque Prolog
%% strings; they are never atom-ized into callable position and never
%% steer rule selection except through classify_target/2 for host
%% values, which is a pure recognizer.
%%
%% Loaded after hackmode_expert.pl (classify_target/2) and the vendored
%% logicStrike KB/inference under expert/logicstrike/.

:- use_module('logicstrike/kb/concepts').
:- use_module('logicstrike/kb/relationships').
:- use_module('logicstrike/kb/techniques').
:- use_module('logicstrike/modules/inference').

%% snapshot_surface(?Kind, ?Value, ?Surface) is nondet.
%% Kind is the CL asset-kind string; Value is only consulted for host
%% assets, whose canonical value may be an IP or a hostname. Unknown
%% kinds map to no surface: no candidates, fail closed.
snapshot_surface("domain", _, domain).
snapshot_surface("url", _, url_input).
snapshot_surface("host", Value, Surface) :-
    classify_target(Value, Type),
    host_surface(Type, Surface).

host_surface(ipv4, ip).
host_surface(ipv6, ip).
host_surface(domain, domain).

%% technique_candidate(?AssetId, ?Method, ?Family) is nondet.
%% Snapshot assets whose bridged surface satisfies a technique's
%% requirement (surface_matches/2 includes the subtype closure, so
%% url_input reaches techniques requiring input). When a query_asset/1
%% fact is present, only that asset is considered.
technique_candidate(AssetId, Method, Family) :-
    (   query_asset(QueryId)
    ->  AssetId = QueryId
    ;   asset(AssetId, _, _)
    ),
    asset(AssetId, Kind, Value),
    snapshot_surface(Kind, Value, Surface),
    technique(_, Method, Family),
    requires_surface(Method, Required),
    surface_matches(Surface, Required).

emit_technique_candidates :-
    findall(Method-Family-AssetId,
            technique_candidate(AssetId, Method, Family),
            Rows),
    sort(Rows, Sorted),
    forall(member(Method-Family-AssetId, Sorted),
           format('~a\t~a\t~a~n', [Method, Family, AssetId])).
