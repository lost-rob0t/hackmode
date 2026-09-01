# Retired Hackmode Auto-RAGE workers

Hackmode no longer owns active Auto-RAGE development workers.

The former `hackmode-rage-database` and `hackmode-rage-hackpert` profiles, their installer, and their PR-lane configuration were retired when the two-worker program moved to `lost-rob0t/prolog-rlm` under the Prolog-RLM feature-freeze program.

Active worker policy now lives in:

```text
lost-rob0t/prolog-rlm/agent-zero/
```

Do not launch or recreate the retired Hackmode profiles from this repository.

## Historical boundary

The product/runtime boundary established during the previous migration remains important for historical maintenance: development-worker orchestration is not a Hackmode Common Lisp subsystem, product API, scheduler, authorization layer, persistence model, or architecture concept.

`forbidden-outside-agent-zero.txt` remains in this subtree as the machine-readable lexical boundary for the checked-out Hackmode product tree. Historical Git commits may contain the prior worker implementation and are not rewritten.

The known-good rollback point immediately before the first historical Auto-RAGE migration attempt remains:

```text
dca7592da8a684696556a89cefe782ee19dddfcc
```

Do not restore the historical product-runtime worker abstractions from later migration commits.
