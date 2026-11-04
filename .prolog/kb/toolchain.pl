%% toolchain.pl — verified local toolchain hazards and their fixes.
%% Every fact below was reproduced and fixed in-session on 2026-09-20.

:- module(toolchain, []).

%% --- ASDF source resolution -----------------------------------------------
%% SYMPTOM: worktree system definitions lose to stale clones; e.g. loading
%% :hackmode compiled ~/common-lisp/common-lisp/hackmode/source/... instead of
%% the worktree. asdf:load-asd BEFORE quickload does NOT win.
%% ROOT CAUSE: ASDF default source-registry scans ~/common-lisp/ tree and
%% outranks *central-registry* pushes. star-lang documents the identical hazard
%% in its ci/with-nix-sbcl.sh header.
%% FIX: environment CL_SOURCE_REGISTRY (highest precedence), repo-first ordering:
%%   CL_SOURCE_REGISTRY="<worktree>//:<star-lang>//:<pinned deps>//"
asdf_hazard(cl_source_registry_env_beats_default_scan).

%% --- Nix client breakage ---------------------------------------------------
%% SYMPTOM: every /nix/store/*-nix-*/bin/nix dies with
%%   libssl.so.3: version `OPENSSL_3.2.0' not found (required by libcurl)
%% ROOT CAUSE: nix closures' own openssl stores were GC'd; ld falls back to
%% /nix/store/vzajrlhsdv2d39s7v6zv09ggajs05gwj-openssl-3.0.11.
%% FIX (verified): LD_LIBRARY_PATH pointing at a surviving 3.6.x openssl and a
%% direct store nix binary; nix-daemon on the socket is alive and serves builds.
nix_client_fix(ld_library_path('/nix/store/yj34vymbqf7mf4lmffipy8jqc4kwr1mc-openssl-3.6.4/lib'),
               nix_bin('/nix/store/i4bv0lvk0gfzllcy2kqgz3iam0aw4c4i-nix-2.34.8/bin/nix')).

%% --- Git transport ---------------------------------------------------------
%% git fetch over https remotes aborts ("remote helper 'https' aborted") on this
%% host; SSH remotes (git@github.com:...) work. Prefer SSH for fetches.
git_transport(ssh_works, https_aborts).

%% --- nixpkgs CL inventory (locked hackmode nixpkgs 7c19f30) -----------------
%% sbclPackages HAS: serapeum local-time nfiles nhooks bordeaux-threads jsown
%% cl-ppcre ironclad dexador sento fiveam str yason pzmq usocket cffi babel ...
%% sbclPackages LACKS: cl-ulid, cms-ulid (gitlab:colinstrickland/cms-ulid@fff8430).
%% sento in nixpkgs snapshot predates current remoting stack (star-lang vendors
%% its own); hackmode pins mdbergmann/cl-gserver@6a510c5 in CI — keep that pin.
nixpkgs_cl_gap([cl-ulid, cms-ulid, cl+ssl]).

%% --- star-cl capability ceiling --------------------------------------------
%% star-cl@b8dfbe2 (== origin/master) is v0.9-only: package starintel provides
%% digest-id + new-domain/new-host/new-url style constructors and the FLAT v0.9
%% envelope. There is no 0.10.1 encoder. Hackmode must own its 0.10.1
%% projection; star-cl remains for digest-id identity only.
star_cl(v090_only, at(b8dfbe2)).

%% --- CI mirror death -------------------------------------------------------
%% nsaspy/* GitHub mirrors of tek9 and star-cl are gone; pins must point at
%% lost-rob0t owners (star-cl verified; tek9 assumed same fix as recon-fold
%% branch commit 4be0e03).
ci_pin_owner(lost-rob0t).

%% --- Common Lisp runtime facts (verified while building :hackmode-actors) ---

%% jsown: plain string-keyed alists serialize as JSON ARRAYS and can crash
%% list-to-json (memory fault on dotted pairs). JSON objects must be built
%% via jsown:empty-object + (setf (jsown:val obj "k") v); parsed objects are
%% (cons :obj alist) — detect with (eq (car x) :obj) before reuse.
jsown_hazard(alists_are_arrays, wrap_headers_with_empty_object).

%% hackmode core convention: outbox "json" parameters are PARSED jsown
%% objects (jsown:val-safe reads _id/dtype from them), not strings.
%% Parse wire strings before hackmode:enqueue-starintel-json.
outbox_consumes(parsed_jsown_objects).

%% tek9:new-database only constructs; call tek9:open-database before use or
%% LMDB:ENV is NIL at first operation.
tek9(new_database_requires_open_database).

%% star-sento-compat runtime-spawn takes options as spread trailing args:
%% (apply #'runtime-spawn port ctx name fn '(:dispatcher :providers)).
%% Passing the plist as one argument fails with a keyword-apply error.
sento_port_options(spread_as_trailing_apply_args).

%% Dynamic (let hackmode:*db*) bindings do NOT cross into Sento actor
%% threads; tests must (setf hackmode:*db* db) globally and restore after.
actor_thread_db(global_setf_not_dynamic_let).

%% prolog-verify: worktree digest hashes tracked diff + names of untracked
%% non-ignored files. Gitignore .prolog/{facts.kb,verify.pl,result.json,
%% .facts.lock,sessions/} or every check rewrites make evidence stale; the
%% observation argv is command([...]) — match member/2 against the inner list.
prolog_verify(digest_covers_untracked_names, wrap_argv_in_command1).
