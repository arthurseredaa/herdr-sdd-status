# Changelog

## 0.1.0

First release.

- SDD progress shown as a `$sdd` token on the orchestrator's herdr pane, read from the SDD ledger and plan.
- Guard that denies `Edit`/`Write` from the orchestrator session while SDD runs; subagents and the SDD workspace are exempt.
- `/sdd-status:off` to release a run by hand.
