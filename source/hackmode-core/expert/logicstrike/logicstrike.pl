:- module(logicstrike, []).
/** <module> LogicStrike facade for interactive queries

Load this one file in SWI-Prolog to access both KB and inference predicates.
*/

:- reexport('kb/concepts').
:- reexport('kb/relationships').
:- reexport('kb/techniques').
:- reexport('kb/goals').
:- reexport('kb/experts').
:- reexport('modules/expert_reasoning').
:- reexport('modules/inference').
:- reexport('modules/tools').
