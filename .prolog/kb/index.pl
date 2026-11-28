%% Hackmode durable KB loader — consult this one file.
%% kb/star_lang_fold.pl     — Star-Lang pentest spec fold (PR #212 era)
%% kb/wireless_fold.pl      — wireless recon fold
%% kb/expert_plane.pl       — expert-plane architecture/invariants (PRs #220/#221)
%% kb/prolog_toolchain.pl   — SWI portability + local gate recipes
%% kb/mcp_fold.pl           — operation MCP surface + tool-run wire contract (mcp/operation-tools cycle)
%% kb/skills_fold.pl        — OpenCode skill suite: canonical home, installer, directives, PR state
%% kb/starintel_ingest_fold.pl — desktop-stack ingest: routes, schema acceptance, provenance contract, outbox behavior, corpus import (verified live 2026-11-24)
%% kb/star_lang_logic_fold.pl — Star-Lang logic backend layer: compile-logic-call, star-logic-ir, registered backends (swi-prolog|lisa|n-prolog), MQI adapter foundation, IPX #63 extraction, N-Prolog backend decision (verified 2026-11-24)
%% kb/zap_fold.pl          — ZAP daemon provider backends: spec-declared probe tools, script contract, daemon traps, e2e recipe (verified 2026-11-25)
%% kb/offsec_fold.pl — hackmode-offsec: payload factory (defpayload/defstage/defblock/defagent/defdropper-backend), multi-handler session engine, Lisp dropper rewriters, censor gate (cycle offsec/revshell-handler, 2026-11-24+)
%% kb/ci_fold.pl — Forgejo CI fold: runner egress limits, on-host dep mirrors (nsaspy/*), lane-workflow API rewrite facts, core gate replication recipe (verified 2026-11-27)
:- [star_lang_fold, wireless_fold, expert_plane, prolog_toolchain, mcp_fold, skills_fold, starintel_ingest_fold, star_lang_logic_fold, zap_fold, offsec_fold, ci_fold].
