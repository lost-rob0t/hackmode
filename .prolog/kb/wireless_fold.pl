% Durable knowledge: wireless recon fold (tools/wireless).
% Verified 2026-09-19 at fold commit 5871c85.

tool_location(wireless, 'tools/wireless').
tool_package(wireless, 'hackmode_wireless').          % was starintel_network in the superseded repo
tool_cli(wireless, 'hm-wireless').                    % was starnet
tool_gate_cmd(wireless, 'cd tools/wireless && .venv/bin/pytest -q').
tool_gate_cmd(wireless, 'cd tools/wireless && .venv/bin/ruff check .').
tool_gate_cmd(wireless, 'cd tools/wireless && .venv/bin/mypy').
tool_venv(wireless, 'tools/wireless/.venv').          % python3.14 host; git-ignored via tools/wireless/.gitignore

% CI: .github/workflows/wireless.yml (wireless-tools), path-filtered on
% tools/wireless/** + the workflow file, python 3.12, editable install with
% dev extras, ruff/mypy/pytest -q.

% Repo boundary pitfall: pip's vendored rich emoji table inside ANY .venv
% contains the forbidden standalone token (an emoji short-name). Boundary
% scans over the worktree must exclude git-ignored runtime dirs to mirror
% the CI tracked-tree check:
%   grep -Riw rage --exclude-dir=.venv --exclude-dir=__pycache__ \
%     --exclude-dir=.pytest_cache --exclude-dir=.mypy_cache \
%     --exclude-dir=.ruff_cache tools/wireless docs/recon
% Empty scan through `bash -c '... || true'` hashes to sha256("\n") =
% 6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d
% (see verify.pl forbidden_token_scan_clean/0).

% Schema lock: repo-root schema/starintel-schema.lock.json (= ../../schema
% from tools/wireless) lands in a separate change. Until it exists
% tests/test_schema_lock.py::test_schema_lock_pending_or_pinned SKIPS
% loudly; once present it fails closed on any non-pending lock. Fold-time
% result: 101 passed, 1 skipped (source repo: 102 passing with its lock).

% Windows recon design docs (canonical slice source, forgejo tracker down):
% docs/recon/windows/{design.md,dtype-mapping.md,issue-slices.json},
% byte-identical to the superseded repo's docs/windows-recon/.
