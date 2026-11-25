%% Prolog toolchain portability + local test recipes (promoted 2026-11-19).
%% Both entries verified by RED/GREEN evidence (PRs #220/#221 cycles).
:- module(hackmode_kb_prolog_toolchain, []).

swi_quirk(multiple_s_files, 'SWI 9.1 (ubuntu-24.04 swi-prolog-nox) silently ignores every -s file after the first; 9.2+/10 load all. Symptom: empty stdout + exit 0 (silent success) in CI only. Fix: consult(File) from the goal, never multiple -s. Docker-repro: swipl:9.1.14 vs swipl:9.2.9').
prolog_trap(if_then_else_first_solution, '(Cond -> true ; Else) commits to the FIRST solution of Cond and never backtracks into alternatives; enumerating alternatives plus a default needs a plain disjunction helper. Bit attack_surface/4: only the first containment child produced rows. Verified by failing test then fix (PR #221)').

%% Local mirror of .github/workflows/core.yml (PR cycles 2026-11-15..19)
local_gate(hackmode_core, 'sbcl + quicklisp; ql:*local-project-directories* MUST be nil (local-projects shadow CI pins); pinned tek9/star-cl at core.yml refs via detached worktrees (e.g. /tmp/opencode/*-pin); CL_SOURCE_REGISTRY=<star-lang>//; LD_LIBRARY_PATH to live nix lmdb+openssl lib dirs (nix store paths are GC-ephemeral — re-resolve when libswipl/liblmdb load fails); then quickload :hackmode-tests + :hackmode-database-tests, test-system :hackmode + :hackmode-database').

%% Scripting traps verified 2026-11-24 during the local core-gate replication
%% (e2e outbox drain test; evidence: root run journal 2026-11-24).
sbcl_trap(script_discards_load, 'sbcl --script implies a fresh toplevel and DISCARDS preceding --load/--eval options: banner prints, script runs without quicklisp, output can vanish while the pipeline exit stays 0 (tail masks it). Put (load "~/quicklisp/setup.lisp") INSIDE the script file and run plain sbcl --script file.lisp').
cl_trap(assert_place_list, 'CL assert syntax is (assert test PLACELIST message); a bare string second arg crashes at MACROEXPANSION ("not of type LIST") before the test ever runs — masking the real state. Use (assert test () "msg")').
asdf_trap(system_name_not_dir, 'quicklisp resolves dist systems only; the hackmode core system is named :hackmode (file source/hackmode-core/hackmode.asd) and depends on :hackmode-database (separate asd) — register every needed asd via asdf:load-asd before quickload; there is no :hackmode-core system').
tek9_pin_recipe(archive_without_checkout, 'core.yml pins tek9@1cb9780 but the primary checkout sits elsewhere; git fetch origin <sha> then git archive <sha> | tar -x -C /tmp dep dir gives the exact pin with zero working-tree changes (star-cl/star-lang/sento/cms-ulid local HEADs already match CI pins).').
