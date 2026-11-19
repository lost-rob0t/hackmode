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

%% scope_inherited(?Child, ?Ancestor) is nondet.
%% Transitive closure over asset_of/2, cycle-safe: each node is
%% visited at most once per derivation.
scope_inherited(Child, Ancestor) :-
    Ancestor \== Child,
    scope_inherited_(Child, Ancestor, [Child]).

scope_inherited_(Child, Ancestor, _) :-
    asset_of(Child, Ancestor).
scope_inherited_(Child, Ancestor, Seen) :-
    asset_of(Child, Mid),
    \+ member(Mid, Seen),
    scope_inherited_(Mid, Ancestor, [Mid|Seen]).

%% zone_scope(?InputId, ?Zone) is nondet.
%% The zone itself plus everything it transitively contains. Plain
%% disjunction — an if-then-else here would commit to the first
%% closure solution and silently drop the rest.
zone_scope(Zone, Zone).
zone_scope(InputId, Zone) :-
    scope_inherited(InputId, Zone).

%% attack_surface(+ZoneId, ?Method, ?Family, ?InputId) is nondet.
%% The red-team query: every asset at or below the zone whose surface
%% satisfies a technique requirement. One new containment edge widens
%% the zone with no rule changes.
attack_surface(Zone, Method, Family, InputId) :-
    zone_scope(InputId, Zone),
    asset(InputId, Kind, Value),
    snapshot_surface(Kind, Value, Surface),
    technique(_, Method, Family),
    requires_surface(Method, Required),
    surface_matches(Surface, Required).

emit_attack_surface :-
    query_asset(Zone),
    findall(Method-Family-InputId,
            attack_surface(Zone, Method, Family, InputId),
            Rows),
    sort(Rows, Sorted),
    forall(member(Method-Family-InputId, Sorted),
           format('~a\t~a\t~a~n', [Method, Family, InputId])).
