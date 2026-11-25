% Durable knowledge: Star-Lang logic backend layer (verified 2026-11-24 at
% star-lang checkout 7db89986 = CI pin 7db89986450d4e513ff4b5c9617bf4d196b3cfb4).
% Source: /home/unseen/starintel/star-lang. Consumed by the IPX proxy design
% (docs/architecture/ipx-proxy.org, PR #227).

logic_compile(compile_logic_call,
              'starlang-compiler/src/logic-policy.lisp: compiles logic calls — operation id/kind, semantic profile, backend policy, bindings, answer/proof policy, required capabilities, required hard limits, budget, isolation — into star-logic-ir. Spec/document packs compile to data IR only; logic compilation is for logic calls, never document packs').
logic_ir(star_logic_ir,
         'star-logic-ir: normalized logic-call IR and backend materialization plans (logic-call record + canonical-json projection)').
logic_backends(registered, ['swi-prolog', 'lisa', 'n-prolog']).
logic_selection(star_logic_protocol,
                'star-logic-protocol: portable logic-backend protocol, descriptors (id/version/build-id/semantic-profiles/capabilities), deterministic selection; n-prolog is exercised in its selection tests with capability named-query — a registered backend id with no materializer implementation yet').
swi_adapter_foundation(star_logic_adapter_swi,
                       'MQI worker ownership only: pinned executable identity (explicit path, --version probe, sha256 digest revalidated before every session open), embedded MQI startup, UTF-8 byte framing, password handling tests, digest-locked trusted bootstrap prolog/star_logic_bootstrap.pl, process-isolated sessions, health, shutdown/reaping. Deliberately NOT implemented as of 7db89986: star.logic.query/1, portable query ops, fact mutation, tabling, constraints, proofs, cancellation escalation, worker pooling/reset. Reference SWI-Prolog 10.0.2, MQI protocol 1.0').
ipx_extraction(star_lang_63,
               'commit 87b4628e (#63): IPX application code was deliberately removed from star-lang — application logic lives in consuming repos; star-lang is the language/compiler/backend substrate').
operator_decision(n_prolog_backend,
                  '2026-11-24: IPX rule system layer 3 targets the Prolog backend path, N-Prolog preferred as sole backend; SWI MQI adapter is the bridge and the worker-ownership reference (pinned identity, session isolation, trusted bootstrap) until an n-prolog materializer lands; near-term Hackpert path stays the one-shot expert-snapshot boundary with no new temp-file coupling. Operator authorized the backend lane; design doc = docs/architecture/ipx-proxy.org (forgejo PR #227)').
operator_statement(starlang_meta_language_vision,
                   '2026-11-24, operator: StarLang future goal is to be a meta language doing many things — the logic backend layer (star-logic-protocol backends, compile-logic-call IR) is one of those things, not a one-off; keep backend work general and substrate-shaped').
backend_lane_started(nprolog_materializer,
                     '2026-11-24: worktree ~/git/worktrees/star-lang-logic-n-prolog-backend (branch logic/n-prolog-backend from main 7db89986); slice 1 = star-logic-adapter-nprolog foundation (worker ownership: pinned identity via npl -v, -r plain-REPL worker, banner handshake, true. canary, halt shutdown; descriptor honest-empty capabilities; no package identity published). Engine observed live: npl 5.20 banner forms, ESC[0m before verdicts in plain REPL, exit 0 on halt. Upstream pin 13d43e0c1b084d736ba15d26f1da085f00224b93 (nix fetchFromGitHub sha256-8+GWpfmhkIXlUg67kZPb1jp2iHnmnvbShtlokFELWUg=)').
