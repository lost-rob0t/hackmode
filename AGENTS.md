# Repository agent boundary

Development-agent framework implementation and terminology are isolated to `agent-zero/**`.

Before editing this repository, read:

- `agent-zero/README.md`
- `agent-zero/forbidden-outside-agent-zero.txt`

Every non-comment token listed in `agent-zero/forbidden-outside-agent-zero.txt` is forbidden, case-insensitively, in **all tracked paths and tracked file content outside `agent-zero/**`**.

This includes source code, symbols, comments, strings, tests, fixtures, snapshots, filenames, directory names, product README text, architecture/design/migration documents, examples, templates, tools, Emacs code, Prolog, shell/configuration files, and `.github/**` workflows.

There is no explanatory-text exception. Outside `agent-zero/**`, use only Hackmode-native product terminology. Do not create product abstractions for development-worker identity, scheduling, lane ownership, task selection, worker scope/authorization, coordination, or lifecycle.

Before committing and before opening/updating a PR, ensure the repository boundary workflow passes. A failure is a correctness failure: remove or rephrase the leakage. Never weaken the denylist check, add product-tree exceptions, or broaden exclusions to make a change pass.
