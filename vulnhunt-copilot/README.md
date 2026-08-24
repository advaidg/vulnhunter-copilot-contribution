# VulnHunter for GitHub Copilot

A port of all three VulnHunter [Claude Code](https://docs.claude.com/en/docs/claude-code)
Skills to **VS Code Copilot [Agent Skills](https://code.visualstudio.com/docs/agent-customization/agent-skills)**,
for interactive use inside VS Code:

| Skill | Phase | Port location |
|---|---|---|
| `/vulnhunt` | Hunt — scan a codebase and emit proven, exploitable findings | `skills/vulnhunt/` (overlay onto `vulnhunt/`) |
| `/vulnhunter-fix` | Fix — TDD remediation from scan results, delivered as PRs | `skills/vulnhunter-fix/` (overlay onto `vulnhunter-fix/`) |
| `/vulnhunt-fix-verify` | Verify — independent, read-only check that a fix actually landed | `skills/vulnhunt-fix-verify/` (overlay onto `vulnhunt-fix-verify/`) |

The headless `vulnhunter-agent/`/`harness/` runtimes are **not** ported — this
covers interactive, in-VS-Code use of all three skills only.

> [!NOTE]
> **Revision history.** An earlier revision of this port shipped `/vulnhunt`
> as a Copilot Chat *prompt file* and ran every phase sequentially in one
> session. That broke in practice: a prompt file's generic search/read tools
> are scoped to whatever workspace is currently open, so it couldn't see a
> separately installed `phases/` folder when scanning a different repo. This
> revision ships all three skills as proper **Agent Skills** instead —
> `SKILL.md` plus supporting files, which Copilot resolves relative to the
> skill package itself, independent of the open workspace — and restores
> genuine **parallel** subagent dispatch using VS Code's
> [Subagents](https://code.visualstudio.com/docs/copilot/agents/subagents)
> feature.

## Why this directory doesn't look like three complete, standalone skills

It isn't — and that's deliberate. `vulnhunt-copilot/skills/<name>/` contains
**only the files that differ from the existing Claude Code skill** of the
same name. Everything else — the vulnerability methodology, the gates and
severity tiers, and (most importantly) `vulnhunter-fix`'s entire tested
Python package — is not Claude-specific, so it isn't duplicated. The
install scripts assemble the real, complete skill at install time by
copying the existing skill directory (**base**) first, then this directory
(**overlay**) on top:

```
install destination = base(vulnhunt/) + overlay(vulnhunt-copilot/skills/vulnhunt/)
```

This means a future fix to, say, `vulnhunter-fix/scripts/preflight.py`
automatically applies to both the Claude Code and Copilot installs, with one
edit and no drift risk — there is exactly one copy of that file in the repo.
It also means this directory's file count is not the whole story: if you're
looking for `vulnhunt-copilot/skills/vulnhunt/phases/phase2_class_inj.md`
and don't find it, that's correct — it's identical to
`vulnhunt/phases/phase2_class_inj.md`, so the overlay doesn't need its own
copy; the installer pulls it from the base directory.

### What's actually overridden, per skill

**`vulnhunt`** — overlay has 7 of 12 base files; these 5 are identical and
come from the base directory unchanged: `phase2_class_inj.md`,
`phase2_class_nav.md`, `phase2_class_log.md`, `phase2b_verify.md`,
`phase3c_fixes.md`.

**`vulnhunt-fix-verify`** — overlay has `SKILL.md` and two phase files
(`phase0_preflight.md`, `phase2_verify.md`); `phase1_extract.md`,
`phase4_emit.md`, and `comment_rules.md` are identical and come from the
base directory. `verify_disposition.schema.json` isn't in either skill's
own base tree — the install scripts copy it in directly from
`vulnhunter-agent/verify_disposition.schema.json`, its actual canonical
location, rather than storing a third copy here.

**`vulnhunter-fix`** — overlay has `SKILL.md`, 6 of 17 prompt files
(`parse_issues.md`, `deliver.md`, `implement.md`, `verify.md`, `parse.md`,
`worker_agent_common.md`), and 8 files with small, deliberate deltas inside
otherwise-shared directories: `scripts/cluster_score.py`,
`scripts/validate_findings_draft.py` (comment wording only — no logic
changes), `templates/pr_body.md`, `templates/pr_body_cluster.md`,
`templates/commit_msg.md` (the `Co-Authored-By` trailer says `GitHub
Copilot` instead of `Claude Code` — this one has a real behavioral
consequence, since it lands in actual git history), `tests/test_graph_build_bugs.py`,
`vulnhunter_fix/graph/build.py`, `vulnhunter_fix/graph/config.py` (a few
comments generalized from "the Claude Code sandbox" to "macOS agent
sandboxes," since VS Code Copilot's terminal tool sandboxes similarly — no
logic changes). Everything else — the remaining `scripts/`, all of
`references/`, the remaining `tests/`, the rest of the `vulnhunter_fix/`
package, `config.json`, `collaborators.json`, `pyproject.toml`, `evals/`,
and the other 11 prompt files — is byte-identical to `vulnhunter-fix/` and
is never duplicated in this repo.

Note that even the 8 delta files above only override *specific files*
inside directories that are otherwise fully shared — the overlay does not
need (and doesn't have) a complete parallel `scripts/`/`tests/`/`vulnhunter_fix/`
tree; the install scripts merge base and overlay at the file level, not the
directory level, so a directory can be mostly-base with a handful of
overlay files inside it.

**If you're changing shared methodology** (anything in the base
directories) and the Copilot behavior needs to diverge as a result, add an
override file here at the matching relative path — the overlay always wins
on conflict during install. If your change doesn't need Copilot-specific
handling, you don't need to touch this directory at all; the install
scripts will pick up your base-directory change automatically.

## Install

macOS/Linux:

```bash
# From the repository root:
./install-copilot.sh      # installs all three skills to ~/.copilot/skills/
./uninstall-copilot.sh    # removes them
```

Windows (from `cmd.exe` or PowerShell — both can run `.cmd` files directly):

```bat
install-copilot.cmd
uninstall-copilot.cmd
```

> [!IMPORTANT]
> **Windows: Copilot's agent terminal needs to run bash, not PowerShell.**
> `SKILL.md` and the phase/prompt files embed bash syntax (`${VAR}`
> expansion, `[ ]` tests, heredocs) in their code blocks. VS Code Copilot's
> agent terminal tool defaults to whatever your workspace's default terminal
> profile is — normally PowerShell or cmd.exe on Windows, neither of which
> understands that syntax. `install-copilot.cmd` handles this automatically:
> if it finds Git for Windows, it sets `chat.tools.terminal.terminalProfile.windows`
> in your VS Code `settings.json` to Git Bash — a setting specific to
> Copilot's agent tool, confirmed against VS Code's own source, that doesn't
> touch your regular integrated terminal's default. It backs up
> `settings.json` first and skips cleanly (with manual instructions printed)
> if Git Bash isn't found or the existing `settings.json` can't be parsed
> safely. **This part of the installer was written and reviewed on macOS,
> not run against a real Windows/VS Code install — verify it did what you
> expect before relying on it**, and see
> `vulnhunt-copilot/scripts/windows/configure-terminal-profile.ps1` if you
> want to run or adapt it yourself.

`install-copilot.sh`/`install-copilot.cmd` assemble each skill at
`~/.copilot/skills/<name>/` from the base + overlay directories described
above — files, not symlinks, same reasoning as the Claude Code installer:
symlinks can break workspace search tooling. No path substitution or VS
Code settings edit is needed beyond the Windows terminal-profile step
above: Copilot auto-discovers Agent Skills from `~/.copilot/skills/` and
resolves a skill's own supporting files relative to its `SKILL.md`,
regardless of which workspace you have open when you invoke it.

`vulnhunter-fix` also ships a real Python package (graph-based analysis,
delivery gates, ~30 helper scripts) — one copy, in `vulnhunter-fix/` at the
repo root, used by both the Claude Code and Copilot installs. Like the
Claude Code installer, `install-copilot.sh` builds it a bundled venv at
`~/.copilot/skills/vulnhunter-fix/.venv` with `jsonschema` and `graphifyy`
pinned to the versions `preflight.py` expects — this needs Python 3.11+
available on your machine. The other two skills are prompt-only; no venv.

Re-run `./install-copilot.sh` after pulling changes to refresh your installed
copy (it rebuilds the venv too).

## Usage

1. Open the repository you want to scan/fix in VS Code.
2. Open Copilot Chat, switch to **Agent** mode.
3. Set the model picker to **Auto** if available — see the model note below.
4. Run one of:
   ```
   /vulnhunt              # scan the current repo
   /vulnhunter-fix         # remediate findings from a prior /vulnhunt scan
   /vulnhunt-fix-verify    # independently verify specific findings were fixed
   ```

`/vulnhunt` walks itself through recon, hunting, verification,
reproduction/fix-strategy, sweep, and report phases, checkpointing each
phase's output to disk under a `*_VULNHUNT_RESULTS_*` directory inside the
scanned repo. It **never modifies the target codebase** — fix strategies are
documented, not applied.

`/vulnhunter-fix` is the one that does modify the target: it creates git
worktrees/branches, writes exploit demos and tests, applies fixes, and opens
real PRs (or forks + PRs in fork mode). It needs `git` and the GitHub CLI
(`gh`, authenticated) in addition to VS Code/Copilot.

`/vulnhunt-fix-verify` is read-only over the code it inspects — see its
**Tool boundary** section below for an important caveat on how that's
enforced (or not) under Copilot.

### Model selection: use Auto

GitHub Copilot's [Auto model selection](https://docs.github.com/copilot/concepts/auto-model-selection)
routes each request to the platform's current best-available reasoning model
based on task complexity, and fails over automatically if a specific model is
degraded or unavailable — which is exactly the behavior these skills want
across long, multi-phase, multi-subagent runs, without hard-pinning to one
named model. Select **Auto** in the model picker before running any of these
skills if your Copilot plan/org policy offers it. If Auto isn't available,
pick the strongest reasoning-tier model you have access to — the discipline
that keeps these skills reliable (falsification in `/vulnhunt`, clustering
and fix synthesis in `/vulnhunter-fix`) depends on frontier-class, multi-step
reasoning; all three were originally tuned against Claude Opus on the Claude
Code side.

Subagents dispatched by any of the three skills inherit the parent session's
model by default (VS Code's subagent model-priority order falls back to
"parent conversation's model" when no explicit override is given) — none of
these ports pin subagent models, so they get the same Auto routing.
`/vulnhunter-fix`'s `parse_issues.md` is the one exception worth knowing
about: it explicitly asks for a frontier-tier subagent for one specific
extraction step (README parsing) because lighter models have measurably
dropped findings there — see that file's porting notes.

## Differences from the Claude Code version

Shared across all three ports:

| Claude Code | This port |
|---|---|
| Skill (`SKILL.md` + supporting files), invoked via `/<name>`, discovered from `~/.claude/skills/`. | Agent Skill (same shape), invoked via `/<name>`, discovered from `~/.copilot/skills/`. |
| Orchestrator dispatches **parallel subagents** via the Task tool. | Dispatches parallel subagents via VS Code's `agent`/`runSubagent` tool — same procedures, same minimum counts where applicable. |
| Skill auto-triggers on natural language (Skill `trigger:` frontmatter), in addition to explicit `/command`. | Agent Skills support the same dual invocation (explicit command, or auto-triggered when the skill's `description` matches the request) — a real capability of Copilot Agent Skills, not something these ports had to build. |
| Reports progress via Claude Code's `/cost` command after each phase. | No equivalent exists in Copilot Chat; the skills just confirm each phase's output files exist. |
| Bash tool. | A terminal tool (`runCommands` or equivalent), gated the same way the upstream skill gates Bash access. |

`/vulnhunt`-specific:

| Claude Code (`vulnhunt/`) | This port (`skills/vulnhunt/` overlay) |
|---|---|
| `SKILL.md` programmatically checks the running model and can tell the user to run `/model opus` mid-session. | Asks the user to select **Auto** (or a frontier model) in the Copilot model picker at start-up — can't switch it for them, but Auto's own failover reduces how much this matters. |
| "Agent-driven" invocation path, where `vulnhunter-agent/`'s headless runtime pre-resolves scan metadata. | Not ported — interactive, in-session metadata resolution only (Step 1 of `SKILL.md`). |

`/vulnhunter-fix`-specific — the most consequential differences, since this skill pushes real commits and opens real PRs:

| Claude Code (`vulnhunter-fix/`) | This port (`skills/vulnhunter-fix/` overlay) |
|---|---|
| `TaskCreate`/`TaskUpdate`/`TaskList` for mandatory task tracking. | VS Code's built-in todo-list tool (`todo_write`/`todo_read`) — confirmed to exist and serve the same purpose. |
| `AskUserQuestion` for structured multi-choice prompts (mode disambiguation, cluster/issue selection, collaboration-loop options). | No confirmed Copilot equivalent. Ported as: present options as a numbered list in chat, ask the user to reply with the number(s) (comma-separated for multi-select), and wait. Functionally the same pause-and-wait; loses the structured button/checkbox UI. |
| Opus/Sonnet/Haiku-specific model gating, incl. `/model claude-opus-4-8`. | Recommends Auto model selection (or the strongest available reasoning-tier model) instead of checking for one named model. Where the upstream skill deliberately routes specific subagent *tasks* to a cheaper vs. stronger model tier (e.g. Haiku for mechanical extraction, Sonnet for shape-variable extraction), this port keeps that tiering — generically, as "lightweight/fast model" vs. "frontier reasoning model" — since the underlying reasoning (cost vs. reliability trade-off) isn't Claude-specific. |
| An entire section of operational discipline for Claude Code's Bash tool's TLS/sandbox failure modes (manual hand-off to the user's own terminal, one command at a time). | Rewritten, not just relabeled: VS Code's terminal tool has its *own*, different sandboxing — confirmed to block network access by default with a **built-in retry-with-confirmation** flow, which the Claude Code Bash tool doesn't have. This port tries that retry first; the manual hand-off is now a fallback, not the first move. See `SKILL.md`'s **`git` + `gh` failure policy** section. |
| `Co-Authored-By: Claude Code (VulnFix)` trailer on commits/PRs. | `Co-Authored-By: GitHub Copilot (VulnFix)` — fixed at the source, in the shared `vulnhunter-fix/templates/` and `prompts/worker_agent_common.md` — leaving the old attribution would have been factually wrong in real git history regardless of which platform produced the commit. |
| `${SKILL_DIR}` resolved automatically by the platform. | No Copilot equivalent exists. Bound explicitly in `SKILL.md` Step 0 (derived from the path the agent read `SKILL.md` from, with a documented fallback default). |
| Scripts, references, templates, tests, and the `vulnhunter_fix` Python package. | Not duplicated as whole directories — see "Why this directory doesn't look like three complete, standalone skills" above. A small number of individual files inside them are overlaid with deliberate deltas (the `Co-Authored-By` attribution in `templates/`, and a few comments in `vulnhunter_fix/graph/` generalized from "the Claude Code sandbox" to "macOS agent sandboxes," since VS Code Copilot's terminal tool sandboxes similarly) — these deltas apply to the Copilot install only, by design, since the comment/attribution difference is specifically about which platform is running. |

`/vulnhunt-fix-verify`-specific:

| Claude Code (`vulnhunt-fix-verify/`) | This port (`skills/vulnhunt-fix-verify/` overlay) |
|---|---|
| Skill `allowed-tools` frontmatter gives a **platform-enforced** guarantee that this skill never gets Bash or network tools — its whole trust model (independent, read-only verification) rests on that. | Copilot Agent Skills (as currently documented) have no confirmed equivalent per-skill tool allow-list field. **This is a real limitation, not cosmetic** — see the skill's **Tool boundary** section. The read-only claim is now instructional (the skill tells the model not to use those tools), not platform-enforced. Disable your terminal/network tools in Copilot Chat's tool picker for the session if you want the same hard guarantee. |
| References `verify_disposition.schema.json` "at the repo root." | That path doesn't actually resolve reliably once a skill is installed standalone. This port's install scripts copy it in from its real location (`vulnhunter-agent/verify_disposition.schema.json`) at install time instead. |

### What was ported as-is

The actual security/remediation methodology in every skill — vulnerability
classes, hard gates, severity tiers, TDD discipline, delivery gates, cluster
scoring, the graph-based analysis package — is not Claude-specific and
carries over unchanged (via the base+overlay install-time merge) or with
only cosmetic terminology tweaks where it does need an overlay override
(e.g. "the Grep tool" → "your search tool"). Each skill's `SKILL.md` (and,
for `/vulnhunt`, `phases/phase2_hunt.md`; for `/vulnhunter-fix`,
`prompts/parse_issues.md`) needed real rewrites for orchestration mechanics;
see the porting notes at the top of those files for exactly what changed and
why.

## Layout

```
vulnhunt-copilot/
├── README.md
├── scripts/windows/configure-terminal-profile.ps1
└── skills/
    ├── vulnhunt/                  # overlay onto ../../vulnhunt/ — installs as ~/.copilot/skills/vulnhunt/
    │   ├── SKILL.md
    │   └── phases/                 (6 of 11 files — the other 5 come from the base directory)
    ├── vulnhunt-fix-verify/       # overlay onto ../../vulnhunt-fix-verify/ — installs as ~/.copilot/skills/vulnhunt-fix-verify/
    │   ├── SKILL.md
    │   └── phases/                 (2 of 4 files — the other 2, plus comment_rules.md, come from the base directory)
    └── vulnhunter-fix/            # overlay onto ../../vulnhunter-fix/ — installs as ~/.copilot/skills/vulnhunter-fix/
        ├── SKILL.md
        ├── prompts/                 (6 of 17 files — the rest come from the base directory)
        ├── scripts/                 (2 files — comment-only deltas; the other ~28 come from base)
        ├── templates/                (3 files — Co-Authored-By attribution; nothing else here)
        ├── tests/                   (1 file — comment-only delta; the rest come from base)
        └── vulnhunter_fix/graph/    (2 files — comment-only deltas; the rest of the
                                       package, including all other __init__.py files,
                                       comes from the base directory)
```

See "Why this directory doesn't look like three complete, standalone
skills" above for the full per-skill list of what's intentionally omitted
and where it comes from instead.

## Requirements

- VS Code with GitHub Copilot Chat, Agent mode, Agent Skills, and Subagents
  enabled. These are actively evolving Copilot/VS Code features — if
  dispatch or discovery doesn't behave as documented here, check your VS
  Code/Copilot Chat version against current docs first.
- A frontier reasoning model available through your Copilot subscription
  (ideally with Auto model selection enabled).
- `/vulnhunt` and `/vulnhunt-fix-verify`: no Python, no network required for
  the skill itself. Terminal-enabled/non-read-only modes need your terminal
  tool available in the chat session.
- `/vulnhunter-fix`: Python 3.11+ (for its bundled venv), `git`, and the
  GitHub CLI (`gh`) authenticated to your target repositories.

## License

Part of the VulnHunter project; licensed under the Apache License, Version 2.0.
See the repository-root [`LICENSE`](../LICENSE).
