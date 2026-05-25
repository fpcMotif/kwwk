# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker (GitHub Issues on `EYHN/kwwk`).

| Canonical role    | Label in our tracker | Meaning                                  |
| ----------------- | -------------------- | ---------------------------------------- |
| `needs-triage`    | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`      | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human` | `ready-for-human`    | Requires human implementation            |
| `wontfix`         | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

`wontfix` already exists on the repo (it's a GitHub default). The other four labels do **not** exist yet and must be created before any workflow applies them — `gh issue edit --add-label` only applies labels that already exist, it does not create them. Bootstrap the four labels once (idempotent, safe to re-run):

```bash
gh label create needs-triage   -d "Maintainer needs to evaluate this issue"  -c fbca04 --force
gh label create needs-info      -d "Waiting on reporter for more information" -c d4c5f9 --force
gh label create ready-for-agent -d "Fully specified, ready for an AFK agent"  -c 0e8a16 --force
gh label create ready-for-human -d "Requires human implementation"           -c 1d76db --force
```

Edit the right-hand column to match whatever vocabulary you actually use.
