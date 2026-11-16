:- module(logicstrike_tools,
          [ tool_assigned_goals/2,
            tool_candidate_techniques/4,
            tool_applicable_techniques/2,
            tool_surface_of/2,
            tool_domains_matching/2
          ]).
/** <module> AgentProlog tool predicates

Read-only entry points for an agentProlog host. Each predicate is a
deterministic-first catalog query: it never dispatches tools, never
spawns processes, and fails closed (empty result set) when the KB has
no answer. An empty result is the escalation signal, not an error.
*/

:- use_module('../kb/experts', [expert_handles/2]).
:- use_module('../kb/goals', [goal/2]).
:- use_module('inference',
              [ candidate_technique/4,
                technique_applies/2,
                target_surface/2,
                domain_matches/2
              ]).

%! tool_assigned_goals(?Expert, ?Target) is nondet.
%  Targets whose assigned objective is in the expert's remit.
tool_assigned_goals(Expert, Target) :-
    goal(Objective, Target),
    expert_handles(Expert, Objective).

%! tool_candidate_techniques(?Expert, ?Target, ?Method, ?Family) is nondet.
%  Catalog techniques the expert can attempt against the target.
tool_candidate_techniques(Expert, Target, Method, Family) :-
    candidate_technique(Expert, Target, Method, Family).

%! tool_applicable_techniques(?Target, ?Method) is nondet.
%  Techniques whose required surface is satisfied by the target.
tool_applicable_techniques(Target, Method) :-
    technique_applies(Target, Method).

%! tool_surface_of(+Target, ?Surface) is det.
%  Classify a typed target into its surface kind. Fails for unknown
%  target shapes: the host should escalate rather than guess.
tool_surface_of(Target, Surface) :-
    target_surface(Target, Surface).

%! tool_domains_matching(?Pattern, ?Domain) is nondet.
%  Domains matched by a TLD-first label-list pattern.
tool_domains_matching(Pattern, Domain) :-
    domain_matches(Pattern, Domain).
