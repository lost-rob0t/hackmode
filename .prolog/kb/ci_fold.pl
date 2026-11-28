%% Durable knowledge: Forgejo CI fold (.github/workflows) — verified 2026-11-27
%% during the ci/forgejo-onhost-pins cycle (full local core gate green at
%% the on-host mirror pins).

ci_rule(runner_no_remote_egress,
        'the git.starintel.actor actions runner cannot reach github.com/gitlab.com: every CI dependency fetch must resolve on-host. 800e738 established this in Sep; the 4be0e03/c71b707 repoint to lost-rob0t/* broke core.yml again — actions/checkout resolves `repository:` against the LOCAL instance (github.server_url), so a missing mirror repo fails the step in ~30s with auth retries and everything after is skipped').
ci_rule(onhost_dep_mirrors,
        'pinned dep mirrors live under nsaspy/: tek9@1cb9780, star-cl@b8dfbe2, star-lang@7db8998, cl-gserver@6a510c5 (branch ci-pin), cms-ulid@fff8430 (branch ci-pin; repo created 2026-11-27 for this cycle). actions/checkout with repository: nsaspy/<mirror> + ref: <pin sha> is the working shape; fetch-by-SHA verified per mirror from the host').
ci_rule(lane_workflow_no_gh,
        'agent-pr-serialization originally used the gh CLI and never once succeeded on this forge (every run failed in <=5s since Nov 4); rewritten to python stdlib urllib against GITHUB_API_URL (/api/v1) with the GITHUB_TOKEN env. Forgejo facts: `permissions:` fields are ignored with a warning, Accept: application/vnd.raw+json is NOT honored on the contents API (decode base64 `content` from plain JSON), and pull listing paginates with limit/page, not per_page').
ci_rule(core_gate_replication,
        'exact local replication of the core.yml ASDF step: raw nix sbcl --no-sysinit; CL_SOURCE_REGISTRY="<worktree>//:<star-lang-mirror>//" (worktree first); ASDF_OUTPUT_TRANSLATIONS="/nix/store:<writable-cache>//;"; quicklisp loaded inside the --script file; ql:*local-project-directories* nil; deps cloned from the nsaspy mirrors at the pins. Full suite (hackmode/database/dns/recon/zap/starlang/mcp test-ops) verified green 2026-11-27 with deps fetched from the mirrors themselves').
