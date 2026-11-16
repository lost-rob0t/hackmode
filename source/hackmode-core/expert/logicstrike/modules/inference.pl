:- module(logicstrike_inference,
          [ candidate_recon/2,
            candidate_technique/4,
            surface_matches/2,
            target_surface/2,
            technique_applies/2,
            domain_matches/2
          ]).
/** <module> Ontology-derived candidate activities and techniques

Catalog inferences only. These rules do not establish that a technique
works against a specific target, and do not dispatch tools.
*/

:- use_module('../kb/concepts', [concept/2]).
:- use_module('../kb/relationships',
              [possible_via/2, informed_by/2, part_of_phase/2, subtype_of/2]).
:- use_module('../kb/techniques', [technique/3, requires_surface/2]).
:- use_module('expert_reasoning', [expert_goal/3]).

%! candidate_recon(?Goal, ?Activity) is nondet.
%  Preserve the original two-hop objective-to-capability-to-activity rule.
candidate_recon(Goal, Activity) :-
    possible_via(Goal, Capability),
    possible_via(Capability, MethodActivity),
    informed_by(MethodActivity, Activity),
    part_of_phase(Activity, recon).

%! candidate_technique(?Expert, ?Target, ?Method, ?Family) is nondet.
%  Find a technique directly associated with an assigned objective.
candidate_technique(Expert, Target, Method, Family) :-
    expert_goal(Expert, Objective, Target),
    technique(Objective, Method, Family),
    concept(Method, technique).

%  Or find techniques reached through a capability and an activity.
candidate_technique(Expert, Target, Method, Family) :-
    expert_goal(Expert, Objective, Target),
    possible_via(Objective, Capability),
    possible_via(Capability, Activity),
    technique(Activity, Method, Family),
    concept(Method, technique).


%! surface_matches(?Surface, ?Required) is nondet.
%  Exact or subtype-derived match against a technique's required surface.
surface_matches(Surface, Surface).

surface_matches(Surface, Required) :-
    subtype_of(Surface, Parent),
    surface_matches(Parent, Required).

%! domain_matches(?Pattern, ?Domain) is nondet.
%  Domains are label lists, TLD-first: [com, example, www].
%  A pattern matches when its labels are a prefix of the domain's —
%  so [com, example] is the wildcard *.example.com, and an exact
%  list is an exact host match.
domain_matches(Pattern, Domain) :-
    Pattern = [_|_],
    append(Pattern, _, Domain).

%! target_surface(?Target, ?Surface) is nondet.
%  Classify a typed target term into its surface kind.
%  Domains are label lists, TLD-first (see domain_matches/2).
target_surface(ip(_, _, _, _), ip).
target_surface(domain(_), domain).
target_surface(url_param(_, _, _), url_input).
target_surface(body_param(_, _), form_input).
target_surface(json_param(_, _), json_input).

%! technique_applies(?Target, ?Method) is nondet.
%  Techniques whose surface requirement is satisfied by the target.
%  Satisfaction goes through surface_matches/2, so a concrete input
%  surface (url_input, form_input, json_input) matches the generic
%  input requirement via the subtype relation.
technique_applies(Target, Method) :-
    target_surface(Target, Surface),
    requires_surface(Method, Required),
    surface_matches(Surface, Required).

