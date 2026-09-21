%% starlang.pl — how to consume the star-lang monorepo (verified 2026-09-20).
%%
%% Canonical checkout used: ~/starintel/star-lang (HEAD == origin/main; user
%% instruction: use the monorepo, use latest). Older copy at
%% ~/common-lisp/star-lang is 151 commits stale — do not build against it.

:- module(starlang, []).

monorepo_checkout('~/starintel/star-lang').
monorepo_pin('09f3b6da', exists_on_github_main).
%% NOTE: local checkout 7db89986 was NOT pushed; pin what the remote serves.

%% ASDF systems a downstream repo should depend on.
system(starlang-compiler).            % parse/expand/validate/compile + actor compiler
system(starlang-runtime).             % deterministic actor runtime, body actors
system(star-actor-protocol).          % service/resource URIs, wire envelopes
system(star-sento-compat).            % optional sento bridge via runtime-port
system(star-canonical-json).
system(star-mailbox).

%% Key entry points (package starlangcompiler unless noted).
api(load-star-form, 2).               % (pathname) -> compiled spec library
api(compile-actor-file, 2).           % one .star file = exactly one actor decl -> IR
api(emit-portable-manifest, 3).       % (library actors) -> wire manifest (:wire-version 1)
api(make-body-actor-definition, 2).   % starlangruntime: actor IR -> spawnable definition
api(spawn, 3).                        % starlangruntime: (runtime definition)
api(make-sento-runtime-port, 1).      % starsentocompat: sento ops behind a port
api(runtime-spawn, 4).                % starsentocompat
api(create-document, 4).              % star-lang.api (prototype): graph type values
api(encode-document, 2).              % camelCase wire JSON — NOT the starintel envelope

%% Actor declaration grammar (closed keyword vocabulary).
actor_option(runtime,   [native, external], required).
actor_option(accepts,   list_of_message_types, required).
actor_option(produces,  list_of_type_names, required).
actor_option(restart,   [permanent, transient, temporary], required).
actor_option(mailbox,   bounded_positive_integer, required).
actor_option(service_uri, string, optional).   % main: star://domain:address:name ONLY; hierarchical star://authority/actor/name is on the feat/72 branch, rejected by main
actor_option(handler,   identifier, optional). % native legacy; mutually exclusive with body
actor_option(capabilities, identifiers, optional).
actor_option(metadata,  lower_camel_scalar_pairs, optional).

%% Rules learned from fixtures:
fixture_pattern(ontology, 'fixtures/starintel-core.star').   % spec-library with documents+predicates+messages
fixture_pattern(actor,    'fixtures/actor-compiler/enrichment-worker.star').
fixture_pattern(service_composition, 'fixtures/ingest/').    % library + actor + .lisp host wiring

%% Import rules (prototype loader, starlang load):
import_digest(sha256_of_file_octets).
import_path_resolution(relative_to_importing_file).
import_cache('~/.cache/star-lang/specs').
import_remote(https_only, requires_explicit_allow_network).

%% Decision: hackmode ontology is SELF-CONTAINED (no imports). Importing
%% org.starintel/core@1 would require vendoring + digest pinning and would drag
%% in a vocabulary (finding/port/service/scope/asn) that 0.10.1 rejects.
