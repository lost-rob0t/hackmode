:- use_module(library(pcre)).

:- dynamic operation/1.
:- dynamic asset/3.
:- dynamic provider/4.
:- dynamic query_target/1.
:- dynamic query_asset/1.
:- dynamic execution_record/9.
:- dynamic operational_kb_entry/11.

classify_target(Input, url) :-
    re_match('(?i)^https?://[^[:space:]]+$', Input), !.

classify_target(Input, ipv4) :-
    re_match('^(?:(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\\.){3}(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})$', Input), !.

classify_target(Input, ipv6) :-
    split_string(Input, ":", "", Parts),
    length(Parts, Count),
    Count >= 3,
    Count =< 9,
    member("", Parts),
    forall(member(Part, Parts), ipv6_part(Part)), !.

classify_target(Input, ipv6) :-
    split_string(Input, ":", "", Parts),
    length(Parts, 8),
    forall(member(Part, Parts), ipv6_part(Part)), !.

classify_target(Input, domain) :-
    re_match('(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$', Input), !.

classify_target(_, unknown).

ipv6_part("").
ipv6_part(Part) :-
    re_match('^[0-9A-Fa-f]{1,4}$', Part).

compatible_kind("any", _).
compatible_kind(Kind, Kind).

recommend(AssetId, Capability, ProviderName, Priority) :-
    asset(AssetId, Kind, _),
    provider(Capability, ProviderName, InputKind, Priority),
    compatible_kind(InputKind, Kind).

recon_capability("subdomain-enumerate").
recon_capability("http-probe").

recon_candidate(AssetId, Capability, ProviderName, Priority) :-
    recon_capability(Capability),
    recommend(AssetId, Capability, ProviderName, Priority).

emit_classification :-
    query_target(Input),
    classify_target(Input, Type),
    format('~a~n', [Type]).

emit_recommendations :-
    query_asset(AssetId),
    findall(Priority-Capability-ProviderName,
            recommend(AssetId, Capability, ProviderName, Priority),
            Rows),
    sort(Rows, Sorted),
    forall(member(Priority-Capability-ProviderName, Sorted),
           format('~d\t~a\t~a~n',
                  [Priority, Capability, ProviderName])).

emit_recon_next_action :-
    query_asset(AssetId),
    setof(Priority-Capability-ProviderName,
          recon_candidate(AssetId, Capability, ProviderName, Priority),
          [Priority-Capability-ProviderName | _]), !,
    format('~d\t~a\t~a~n', [Priority, Capability, ProviderName]).
emit_recon_next_action.
