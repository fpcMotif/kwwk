# Best Practices — PRD Quality Bar, Scope Discipline, Risk Register

Guardrails for keeping this PRD honest and the product focused, plus the full risk
register behind the [§9 Go/No-go verdict](./_index.md#9-go--no-go-verdict).

---

## 1. PRD quality bar (what the old README-as-spec lacked)

A KWWK PRD section is "done" only when it states:

1. **Problem** before solution.
2. **Who** it's for (ICP), explicitly excluding who it isn't for.
3. **Why us** (the wedge) in one sentence a competitor couldn't also claim.
4. **What we won't do** (non-goals) — as load-bearing as the goals.
5. **How we'll know** (a measurable leading indicator, even if currently un-instrumented).
6. **Tier + role** for every feature (Now/Next/Later × HERO/PARITY/SPRAWL).

If a proposed feature can't be tagged HERO or justified as bounded PARITY, it defaults to
SPRAWL and needs an explicit defense to enter scope.

---

## 2. Scope-discipline guardrails

- **The parity ratchet is the enemy.** Every Raycast feature we chase is maintenance we
  carry forever for zero differentiation. Match parity to *credibility*, then stop.
- **One wedge feature > ten parity features.** Roadmap reviews should show net HERO
  investment increasing, not parity surface.
- **New artifact type? Justify against the unified model** ([architecture §5](./architecture.md))
  before adding a parallel file + CLI subcommand family.
- **Docs discipline:** the README must not silently become the spec again. Product
  decisions live here; the README documents *shipped* behavior only.

---

## 3. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | **Scope dilution** — parity/sprawl outpaces HERO; product becomes "a launcher with many features" instead of "the unified agent." | High | High | The HERO/PARITY/SPRAWL tiering; freeze parity; prune sprawl (calc/window/conversion); track net HERO investment. |
| R2 | **OAuth/ToS fragility** — reusing vendors' first-party OAuth client IDs may violate ToS and can be revoked/rotated without notice. | Med–High | High | Make API-key path first-class; treat subscription-OAuth as best-effort; never base monetization on it; document plainly (README already hedges); consider local models (B10) as a hedge. |
| R3 | **Maintainability** — 69 KB action file + 9× duplicated artifact surfaces. | High | Med | Unified `SavedArtifact` model ([architecture §5](./architecture.md)); fold aliases in. |
| R4 | **Differentiation erosion** — Raycast/Warp ship a real terminal agent + bridge. | Med | High | Lean into open + BYO + SDK + scriptability (things a closed commercial product won't match); ship B1/B2 to widen the moat. |
| R5 | **Discovery failure** — the wedge is buried in action panels and dense docs; users treat KWWK as just a launcher. | High | High | Surface bridging in primary UI; onboarding that demonstrates a GUI→CLI→GUI loop; measure bridge usage (PRD §7). |
| R6 | **Unmeasurable success** — no telemetry, so PRD §7 metrics can't be validated. | High | Med | Decide on opt-in analytics (open question); until then, treat metrics as qualitative hypotheses, not KPIs. |
| R7 | **macOS-only GUI caps TAM.** | Certain | Low (by design) | Accepted — matches ICP/non-goals; revisit only after core stabilizes. |
| R8 | **Bus factor** — apparently single-maintainer for a wide surface. | Med | Med | Scope discipline (R1) *is* the mitigation; less surface = less to maintain. |

---

## 4. ToS / legal note (expands R2)

`Sources/KWWKAI/OAuthProviders.swift` reuses the OAuth client IDs (and, for Google, the
client secret) shipped by upstream first-party CLIs (Claude Code, Codex CLI, Gemini CLI,
Copilot). The README correctly frames these as non-secret and vendor-owned. For the PRD
the implications are:

- **Not a stable foundation.** Any vendor can rotate/revoke or change ToS, breaking the
  subscription-login flow overnight. Engineering must degrade gracefully to API keys.
- **Reputational/legal exposure.** "Log in with your existing subscription" via another
  vendor's client ID is a gray area. Keep the disclaimer prominent; avoid marketing that
  implies endorsement or that the subscription path is guaranteed.
- **Monetization constraint.** Do not build paid features that *depend* on subscription-
  OAuth working. Anything charged-for must stand on the API-key (or local-model) path.

---

## 5. Security & safety (product-level)

- The agent runs shell/edit/write tools with real filesystem access. The SDK hooks
  (`beforeToolCall`) are the right place for guardrails — promote them to a user-facing
  policy (brainstorm **B6**) before encouraging unattended/background runs (B4).
- Bounded-context rules (large/binary files omitted, not pasted) are already correct —
  keep them as invariants in the BDD suite.
- Never log tokens or `~/.kwwk/oauth.json` contents in launcher streams or history files.
