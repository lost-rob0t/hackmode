%% Expert plane — architecture and invariants (promoted 2026-11-19).
%% Sources: PRs #220/#221 (RED/GREEN + prolog-verify), operator stances.
:- module(hackmode_kb_expert_plane, []).

%% Authority and effects
expert_invariant(no_second_store, 'the operation Tek9 store is the single engagement KB: assets + execution graph + operational KB + containment records. The expert layer only snapshots in and proposes deltas out; it never owns storage').
expert_invariant(effect_gate, 'expert-engine PASSIVE/ACTIVE + effect kinds outrank any Prolog-side gating; emit_* goals are advisory (:reasoning only)').
expert_invariant(snapshot_values_inert, 'snapshot classification keys only on the CL-owned asset-kind vocabulary; snapshot values are opaque Prolog strings, never goal-concatenated or atom-ized into callable position').

%% Snapshot API shape
expert_api(wrapper_shadow, 'expert-snapshot is REDEFINED by expert/state-snapshot.lisp around *base-expert-snapshot-function* (expert.lisp). Extending the base lambda list requires forwarding the new key through the wrapper too — symptom of missing this: UNKNOWN-KEYWORD-ARGUMENT at runtime despite a correct base definition').
expert_api(containment_facts, 'containment reaches Prolog as asset_of(ChildId, ParentId) string facts from typed records (fetch-asset-containment), sorted by child id for determinism').

%% Data model
containment_model(node_not_edge, 'containment rows are typed NODES (:kind :asset-containment) in the hackmode/assets/<operation-id> graph, not edges — avoids the Tek9 cross-graph edge constraint (edges cannot target nodes absent from their graph; #61 lesson) and keeps identity (operation, child, parent) replay-safe').

%% Queries
expert_query(attack_surface, 'attack_surface(Zone, Method, Family, InputId) — zone itself plus transitive descendants whose surface satisfies a technique requirement; the red-team-first operator stance made this the first offense-native query').
operator_stance(red_team_first, 'all expert-plane work is designed offense-first; blue-team projections derive from the same graph later, never designed first').

%% Sequenced next
expert_next(tek9_prolog_native, 'operator-approved destination: embedded libswipl + virtual predicates (asset/3, asset_of/2 resolved live from the store) in the tek9 repo; snapshot temp files disappear and the SWI -s portability class dies with them').
expert_next(slice_b_delta, 'graph-delta acceptance layer designed in docs/architecture/expert-containment-delta.org; first delta families are offense-loop state (plan edges, failed-on-condition negative evidence)').
