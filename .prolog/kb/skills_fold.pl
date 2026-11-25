%% OpenCode skill suite fold (skills/opencode-suite cycle, 2026-11-24).
%% Canonical facts for agents operating or extending the Hackmode skill suite.

%% Canonical location and install contract.
skill_suite_home('~/starintel/hackmode/.opencode/skills').
skill_suite_installer('tools/install-opencode-skills.sh').
skill(install_targets, [repository('nsaspy/star-bbp-lab', 'git.starintel.actor'), repository('starintel-labs/star-bbp', 'git.starintel.actor')]).
skill_suite_member(setup).      % build hm/hm-mcp, MCP registration, template install
skill_suite_member(operations). % op tools, fail-closed scoping, lossless invariant
skill_suite_member(recon).      % capability discovery, declared run tools, assets
skill_suite_member(templates).  % bbp/op/htb consumption contracts
skill_suite_member(bbp).        % BBP-as-operation scope discipline + phases
skill_suite_member(wireless).   % hm-wireless collectors, publisher contract

%% Operator directive 2026-11-24 (skills):
%% skills teach RUNTIME DISCOVERY (capability_list, tools/list, --help);
%% they never hardcode tool-status tables and never carry dev-state prose
%% (slice numbers, tracker ids, PR references, "pending slice", tracked gaps).
%% Enforced by the no-dev-state grep requirement in the skills-suite
%% prolog-verify run; keep the requirement when editing skills.
skill_suite_rule(discovery_first).
skill_suite_rule(no_dev_state_prose).

%% Boundary: the suite lives outside agent-zero/**, so the lexical token
%% check applies to every skill file; keep the boundary-clean requirement.
skill_suite_rule(boundary_clean).

%% Installed copies are byte-mirrors; verify installs with diff -r against
%% the canonical tree, not by eyeballing.
skill_suite_rule(installed_copies_are_mirrors).

%% PR state at cycle end (update after merge).
skill_suite_pr(hackmode, 'https://github.com/lost-rob0t/hackmode/pull/223').
skill_suite_pr('star-bbp-lab', 'https://git.starintel.actor/nsaspy/star-bbp-lab/pulls/1').
skill_suite_pr('star-bbp', 'https://git.starintel.actor/starintel-labs/star-bbp/pulls/2').
