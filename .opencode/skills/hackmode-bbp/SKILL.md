---
name: hackmode-bbp
description: Run bug-bounty (BBP) work as a Hackmode operation — bbp template scope discipline, phases, methodology checklists, and how the operation workspace relates to star-bbp-lab research gates; run this skill for any bug-bounty program engagement
---

# hackmode-bbp — bug bounty as a Hackmode operation

BBP work runs as a Hackmode operation next to the other operations
(default root `~/hackmode/`). The `bbp` template seeds the program
operation; recon runs go through the canonical provider path
(hackmode-recon); disclosure and bounty decisions stay with the operator.

## Operation setup

1. Create the operation (hackmode-templates): `op_create` + copy
   `templates/bbp/` (or use the Emacs client).
2. Fill `operation.org` identity: program name, platform, policy URL.
3. Fill the `#+NAME: scope` table (target | kind | in-scope | notes), run
   the export babel block → `.config/targets.txt`; every out-of-scope
   entry goes to the *Out of scope* table AND `.config/blacklist.txt`.
4. `op_use` the operation before any run tool so findings persist into
   the right store.

## Scope discipline (does not bend)

- Read the program policy before the FIRST request; record rate limits,
  banned techniques, and disclosure terms in operation.org.
- In-scope targets only; the scope table and blacklist are the
  operator's word. A target missing from the table is out of scope.
- `HACKMODE_PATH`/`HACKMODE_OP` (.envrc) and `.config/targets.txt` are
  what tools and clients read — keep them in sync with the table.

## Phases (operation.org)

1. *Recon* — scope frozen; subfinder/crt.sh (`:subdomain-enumerate`),
   massdns (`:dns-resolve`); feed results back into the scope table.
2. *Freebies* — easy misconfigurations first; see methodology.org.
3. *Vuln class passes* — one class at a time, checklist driven.
4. *Report* — draft in `reports/`, submit, track in the rewards table.

## methodology.org

The checklist is coverage-annotated: each section names its Hackmode
backends and what is manual. Follow it as written: tool-backed items run
through the declared MCP tools (confirm readiness with `capability_list`
first); manual items stay manual — do not "promote" a manual item by
shelling out around the catalog (that breaks the evidence trail). Payload
bodies live in linked roam nodes; the template links, it does not
duplicate.

## Relation to star-bbp-lab research

The lab repo (`~/starintel/star-bbp-lab`) owns target dossiers, fuzzing,
advisories, disclosure, and bounty claims, with its own method gates and
operator validation stages. When a BBP operation feeds the lab:

- The operation workspace hosts recon state and findings-in-progress;
  the lab owns advisories and the disclosure runbook.
- Lab gates (spec sweep → historical exploit-path recon → dependency
  audit → downstream map) and the five operator validation stages are NOT
  satisfied by anything in the operation store — agents never
  self-approve a disclosure, PoC release, or bounty claim.
- No PoC, crash dump, or advisory text leaves the lab before its CVD
  runbook allows it, even if the operation found it.
