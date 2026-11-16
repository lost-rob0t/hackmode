:- module(logicstrike_expert_reasoning, [expert_goal/3]).
/** <module> Resolve assigned expert goals from the KB */

:- use_module('../kb/experts', [expert/1, expert_handles/2]).
:- use_module('../kb/goals', [goal/2]).

%! expert_goal(?Expert, ?Objective, ?Target) is nondet.
%  The expert is registered, handles Objective, and that goal is assigned.
expert_goal(Expert, Objective, Target) :-
    expert(Expert),
    expert_handles(Expert, Objective),
    goal(Objective, Target).
