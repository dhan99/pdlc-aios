# Invariant Verification Record — pdlc-aios

**Purpose:** evidence that the platform-enforced invariants actually hold, tested adversarially rather than assumed. This is ADAF Gate-0 exit evidence ("a trivial agent change is blocked by each invariant when it should be").
**Repo:** `dhan99/pdlc-aios` (private, GitHub Pro) · **Date:** 2026-08-__ · **Tester:** Dhan
**Place in repo at:** `docs/architecture/invariant-verification.md`

---

## Configuration under test

| Control | Setting | Enforces |
|---|---|---|
| Branch protection (`main`) | PR required · 1 approving review · code-owner review · required check `test` · `enforce_admins: false` · no force-push · no deletion | No direct pushes; no unreviewed merges |
| CODEOWNERS | `* @dhan99` | The approver must be the code owner |
| Ruleset `branch-namespace-fence` | Creation/update denied outside `main`, `agent/**`, `feat/**`, `chore/**` | Agents confined to their namespace |
| Workflows | `test`, `claude-review` (review + security), `claude` (@claude) · `permissions:` least-privilege + `id-token: write` · `--max-turns` set | CI agents bounded and scoped |
| Identities | Human `dhan99` · `pdlc-agent-bot[bot]` (dispatcher, App-token) · `claude[bot]` (Anthropic review App) | Attributable, separately-scoped actors |

**Solo-developer note:** `enforce_admins: false` is deliberate. The bot is not an admin, so it remains fully bound; the human author uses an explicit, logged admin bypass (`gh pr merge N --squash --admin`) because GitHub never permits self-approval. In a multi-developer configuration this flips back to `true` and the bypass disappears.

---

## Pre-Block-6 results (human-side gates)

| # | Check | Command | Expected | Result | Evidence |
|---|---|---|---|---|---|
| S1 | Human pushes to protected main | `git commit --allow-empty && git push origin main` | Rejected | ✅ PASS | `GH006: Protected branch update failed — Changes must be made through a pull request. Required status check "test" is expected.` |
| S2 | Human creates out-of-namespace branch | `git checkout -b randomname && git push origin randomname` | Rejected | ✅ PASS | `GH013: Repository rule violations — Cannot create ref due to creations being restricted.` (local branch created; remote ref never existed) |
| S3 | Human creates sanctioned branch | `git push origin feat/fence-test` | Allowed | ⬜ | |
| S4 | Human self-approval attempt | Approve own PR in UI | Rejected | ✅ PASS | "Pull request authors cannot approve their own pull requests" |
| S5 | Least-privilege fails closed | `claude-review` without `id-token: write` | Job fails, does not run with broad default | ✅ PASS | `Could not fetch an OIDC token. Did you remember to add 'id-token: write'…` — fixed in PR #5 |

---

## Block 6 — Adversarial matrix (bot identity)

Setup (single shell session; installation tokens expire in ~1 hour by design):

```bash
cd ~/workspace/github/pdlc-aios
TOKEN=$(uv run python scripts/mint_bot_token.py <APP_ID> <INSTALL_ID> ~/.secrets/pdlc-agent-bot.pem)
echo ${TOKEN:0:8}                     # ghs_ → good
git clone "https://x-access-token:$TOKEN@github.com/dhan99/pdlc-aios.git" /tmp/botwork
cd /tmp/botwork
git config user.name  "pdlc-agent-bot[bot]"
git config user.email "<APP_ID>+pdlc-agent-bot[bot]@users.noreply.github.com"
```

| # | Attack | Command | Expected | Result | Evidence (paste error/output) |
|---|---|---|---|---|---|
| A | Bot pushes to main | `git commit --allow-empty -m x && git push origin main` | **Rejected** (branch protection) | ⬜ | |
| B | Bot pushes outside namespace | `git checkout -b sneaky && git push origin sneaky` | **Rejected** (ruleset) | ⬜ | |
| C | Bot pushes to its namespace | `git checkout -b agent/inv-test && git commit --allow-empty -m "test" && git push origin agent/inv-test` | **Allowed** | ⬜ | |
| D | Bot opens a PR | `curl -s -X POST -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/dhan99/pdlc-aios/pulls -d '{"title":"invariant test","head":"agent/inv-test","base":"main"}' \| jq '{number, html_url, user: .user.login}'` | **Allowed**; author = `pdlc-agent-bot[bot]`; `test` + `review` + `security` start | ⬜ | PR #___ |
| E | Bot approves its own PR | `curl -s -X POST -H "Authorization: token $TOKEN" https://api.github.com/repos/dhan99/pdlc-aios/pulls/<N>/reviews -d '{"event":"APPROVE"}'` | **Rejected** (author cannot self-approve; and a bot approval could not satisfy the code-owner rule regardless) | ⬜ | |
| F | Merge without approval | Attempt merge in UI as human | **Blocked** — needs code-owner approval + green checks | ⬜ | |
| G | Agents show up | View PR #N | AI review comments + security scan comment present | ⬜ | |
| H | @claude responds | Comment `@claude what does this PR change?` | Reply from the action within minutes | ⬜ | |

**Close the loop (the intended production path, end to end):** approve PR #N yourself → checks green → merge normally (no `--admin` needed; you are not the author) → **bot proposes, human disposes**.

Cleanup:
```bash
git push origin --delete agent/inv-test
rm -rf /tmp/botwork
# token expires on its own — never stored, never reused
```

---

## Block 7 — Negative control

A gate that blocks everything is as broken as one that blocks nothing. Normal human flow must stay frictionless.

| # | Check | Expected | Result | Notes |
|---|---|---|---|---|
| N1 | `feat/*` branch → push → `gh pr create` | Smooth, checks run automatically | ⬜ | |
| N2 | Review agents comment on a human PR | Comments present, non-blocking | ⬜ | |
| N3 | Human merges own PR via admin bypass | Succeeds, logged | ⬜ | `gh pr merge N --squash --admin` |

---

## Findings & deviations

| ID | Finding | Impact | Action |
|---|---|---|---|
| F1 | `claude-code-action` requires `id-token: write` (OIDC) — absent from initial workflows | Review agent could not authenticate | Fixed in PR #5; both workflows updated |
| F2 | `claude-code-action` additionally requires the official **Claude GitHub App** installed on the repo for App-token exchange | Review agent failed after OIDC succeeded | Installed via `claude /install-github-app` (Actions setup step skipped — custom workflows already existed) |
| F3 | Branch protection/rulesets on private repos require a paid plan | Enforcement unavailable on Free | Upgraded to GitHub Pro; repo kept private |
| F4 | `enforce_admins: true` blocks the solo author entirely (cannot self-approve, cannot bypass) | Own PRs unmergeable | Set `enforce_admins: false`; bot unaffected — documented above as deliberate |
| F5 | | | |

---

## Sign-off

- [ ] All Block-6 rows executed with expected outcomes
- [ ] Block-7 negative control passed
- [ ] First bot-authored PR merged through the full path (bot PR → checks → human approval → merge)
- [ ] Bot token minted fresh, used, expired — never stored
- [ ] Cleanup complete: no stray branches (`git branch`, `git branch -r`), `gh pr list` empty

**Verified by:** ______________  **Date:** ____________

Re-verify after any change to: branch protection, rulesets, CODEOWNERS, workflow `permissions:`, or agent identity configuration.
