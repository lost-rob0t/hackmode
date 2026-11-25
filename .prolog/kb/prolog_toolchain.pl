%% Prolog toolchain portability + local test recipes (promoted 2026-11-19).
%% Both entries verified by RED/GREEN evidence (PRs #220/#221 cycles).
%% Plain facts (no module): queried from the shared KB context like mcp_fold.
:- discontiguous swi_quirk/2, prolog_trap/2, local_gate/2, sbcl_trap/2, cl_trap/2, asdf_trap/2, tek9_pin_recipe/2, cl_fmt/2, format_trap/2, host_trap/2.
:- multifile cl_trap/2, asdf_trap/2.

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

%% Verified 2026-11-24/25 during the offsec/revshell-handler cycle.
sbcl_trap(noninteractive_script_skips, 'sbcl --non-interactive --script file.lisp silently SKIPS the script (banner prints, exit 0, no output): --non-interactive before --script discards it. Run plain sbcl --script file.lisp and put everything inside the script').
sbcl_trap(fasl_cache_stale_package, 'ASDF served a stale package.fasl after exports changed: new packages/symbols missing at compile time of dependent systems with no obvious cause. Force (asdf:compile-system :sys :force t) or clear ~/.cache/common-lisp when exports/packages change; the runtime error is "Symbol X not found in the PACKAGE" far from the edit').
host_trap(source_registry_conf, 'the host source-registry conf (~/.config/common-lisp/source-registry.conf.d/10-workspace.conf) pins ~/starintel/hackmode AHEAD of everything: find-system :hackmode resolves to the PRIMARY checkout even after asdf:load-asd of a worktree asd, and stale-system symptoms follow. Gates MUST export CL_SOURCE_REGISTRY="<worktree>//:<pins>//" to scope resolution; assert (asdf:system-source-file :sys) points at the worktree before compiling').
cl_trap(ironclad_base64_missing, 'the host ironclad does not export usb8-array-to-base64-string / base64-string-to-usb8-array (only byte-array-to-hex-string, hex-string-to-byte-array, make-random-salt): implement base64 self-contained when needed; keeps generated payloads dependency-free too').
cl_trap(make_keyword_absent, 'make-keyword is serapeum, not CL: (intern (string-upcase s) :keyword) or import from serapeum').
cl_trap(reader_pkg_prefix_leak, 'printing symbols homed in package P while *package* is another package emits P::sym - any generator that prints Lisp source must run under the same package its symbols were interned in (see offsec_fold dehome trap)').
format_trap(tilde_at_newline, 'format "~@\n" drops the newline but KEEPS following indentation; plain "~\n" drops newline AND indentation - use plain tilde-newline to build single-line shell one-liners, or you emit IndentationError-prone python -c payloads').
cl_fmt(formatter_setup, 'nested format strings that contain ~s of user data must round-trip via prin1/read; package-qualified unexported symbols print HACKMODE-OFFSEC::SYM and break wire protocols that match symbols by name - emit plain lowercase symbols (format ~(~a~) or literal strings) so the peer reads them in its own package').
