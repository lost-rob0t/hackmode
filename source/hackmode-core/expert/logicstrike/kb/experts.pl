/** <module> LogicStrike expert registry */

:- module(logicstrike_experts,
          [ expert/1,
            expert_handles/2
          ]).

expert(logicstrike).

expert_handles(logicstrike, recon).
expert_handles(logicstrike, foothold).
