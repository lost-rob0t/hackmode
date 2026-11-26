% Durable knowledge: Star-Lang pentest tool fold (source/hackmode-starlang).
% Verified 2026-11-02 at hackmode PR #212 (CI common-lisp-core green,
% local gate green against exact CI pins) on 9224197.

system_location(hackmode_starlang, 'source/hackmode-starlang').
spec_library(hackmode_starlang, 'org.hackmode/pentest@1').
spec_path(hackmode_starlang, 'source/hackmode-starlang/spec/pentest.star').
spec_gate(hackmode_starlang, 'strict loader via star-lang.api:load-star-file (runs inside hackmode-starlang-tests); starlang-cli check is for actor programs only and rejects bare spec-libraries').
cl_gate(hackmode_starlang, 'asdf:test-system :hackmode-starlang (CI common-lisp-core job; core.yml)').
ci_pin(hackmode_starlang, 'lost-rob0t/star-lang@7db89986450d4e513ff4b5c9617bf4d196b3cfb4 -> deps/star-lang-ci, recursive CL_SOURCE_REGISTRY entry ending //').

% star-lang consumption contract (verified against the pinned commit):
starlang_api_used(hackmode_starlang,
                  ['star-lang.api:load-star-file',
                   'star-lang.api:create-document',
                   'star-lang.api:encode-document',
                   'star-lang.loader:loaded-graph-root',
                   'star-lang.loader:library-node-compiled',
                   'star-lang.loader:library-node-name',
                   'star-lang.loader:library-node-version']).
starlang_rule(strict_loader_digests,
              'import digests must be full sha256:<64 hex>; fixture placeholder digests are rejected, so product libraries stay self-contained (org.hackmode/pentest@1 has zero imports)').
starlang_rule(ir_shape,
              'compiled IR is a plist: :name/:version/:declarations; declarations carry :kind :enum|:document|:message, :name, :qualified-name, :values (enums) or :fields ((:name "runId" :type ... :required t) ...)').
starlang_rule(document_construction,
              'create-document takes kebab-case keyword keys and camelCases them (:run-id -> "runId"); a non-empty :dataset is mandatory; encode-document returns a lowerCamelCase alist').
starlang_rule(nested_asdf_systems,
              'star-lang in-tree systems live in nested dirs (star-actor-protocol/, star-canonical-json/, ...): a flat central-registry push cannot find them — use a recursive registry entry ending //; ql:quickload cannot resolve in-tree non-dist systems at all, load via asdf:load-system').
starlang_rule(nix_sbcl_wrapper_hazards,
              'sbcl.withPackages wrapper: internal registry points at ~/common-lisp (stale older checkout) and prefixes store output translations; follow star-lang ci/with-nix-sbcl.sh (probe pristine env, exec raw sbcl, repo-first registry); adding /usr/lib to LD_LIBRARY_PATH breaks nix sbcl (GLIBC_PRIVATE __pointer_chk_guard) — use nix lmdb/openssl store libs instead').
local_gate_recipe(hackmode_starlang,
                  'raw sbcl --no-sysinit; registry = hackmode system dirs + pinned deps (star-cl/src, tek9/src, sento, cms-ulid) + star-lang worktree + wrapper store registry; ASDF_OUTPUT_TRANSLATIONS maps /nix/store/ to a writable cache FIRST; quicklisp at ~/quicklisp loaded per-run like CI').

provider_rule(hackmode_starlang,
              'recon providers are delegated (register-pentest-providers soft-calls hackmode-provider-recon when loaded), never duplicated; nuclei is the first vuln backend (:vuln-scan, input hackmode:domain, output hackmode:finding)').
evidence_rule(hackmode_starlang,
              'nuclei findings keep the exact JSONL source line as finding data (lossless capture invariant applied to offensive tooling output)').
regression_rule(hackmode_starlang,
              'registry/kali wrapper_status must not claim first-party for star-lang-declared tools until those tools actually emit StarIntel documents from this repository').

%% System-domain rate-limit fold (branch starlang/system-rate-limits, 2026-11-26).
spec_library(hackmode_starlang_system, 'org.hackmode/system@1').
spec_path(hackmode_starlang_system, 'source/hackmode-starlang/spec/system.star').
spec_gate(hackmode_starlang_system, 'same strict loader gate as the pentest library: run-system-library-test inside hackmode-starlang-tests loads spec/system.star at the CI pin').
starlang_rule(system_rate_limit_shape, 'max-rate-limit declares BOTH maxima in one declaration: maxPerHost and maxPerIp over one windowSeconds; declare-rate-limit is the actor-domain message carrying the same fields. Egress awareness is required because proxy lists and rotating tor (docker) exist: egress-kind is (direct|proxy-list|rotating-tor), optional, default direct').
starlang_rule(pinned_loader_defaults, 'verified at CI pin 7db8998: the compiler accepts :optional :default and integer :minimum, and create-document applies declarative field defaults (apply-field-defaults in document-runtime.lisp), so omitting egress encodes "direct"').
