# Install i-have-work

Authoritative source: `https://git.skea.io/S/skills` (Gitea).
[`github.com/eynov/skills`](https://github.com/eynov/skills) is a read-only mirror — see
[NOTICE.md](./NOTICE.md).

## Recommended: the managed installer

```bash
git clone https://github.com/eynov/skills.git    # or https://git.skea.io/S/skills.git
cd skills
bash install.sh
```

`install.sh` is a shorthand for `skills.sh install`. It detects Claude Code and Codex, installs
for whichever it finds, and leaves the skill on-demand unless you ask otherwise.

```bash
bash skills.sh install      bash skills.sh status     bash skills.sh enable
bash skills.sh update       bash skills.sh doctor     bash skills.sh disable
bash skills.sh uninstall    bash skills.sh help
```

Add `--claude`, `--codex`, or `--all` to target specific agents; `--permanent` /
`--no-permanent` to control permanent mode; `--source auto|gitea|github` to choose the
Claude Code plugin source. Run `bash skills.sh help` for the full reference.

**Source selection.** With `--source auto` (the default) the installer prefers whichever host
this clone came from and falls back to the other if it is unreachable. Forcing
`--source gitea` or `--source github` disables that fallback — if the forced host is down, the
install fails loudly rather than quietly using the other one.

**`update` scope.** `skills.sh update` redeploys the copy in this repository. It never runs
`git pull`, so it works from a Gitea clone, a GitHub clone, a ZIP export, or a read-only
mount. Update the repository yourself first if you want newer content.

The rest of this document covers the manual routes, which remain fully supported if you prefer
to drive the agent CLIs yourself.

## Manual installation

<details open>
<summary><strong>Claude Code</strong></summary>

### Install

```bash
claude plugin marketplace add https://git.skea.io/S/skills.git
claude plugin install i-have-work@skills
```

Type `/i-have-work`.

Prefer not to add a marketplace? Drop the plugin directly into your personal skills
directory instead — no marketplace step needed:

```bash
git clone https://git.skea.io/S/skills.git /tmp/skills
cp -R /tmp/skills/plugins/i-have-work ~/.claude/skills/i-have-work
```

It auto-loads next session as `i-have-work@skills-dir`. Run `/reload-plugins` to load it
immediately in the current session.

### Verify

```bash
claude plugin list
```

Look for `Status: ✔ enabled` (marketplace install) or `Status: ✔ loaded` (skills-dir).

### Update

```bash
claude plugin marketplace update skills
claude plugin update i-have-work@skills
```

Both steps are required: `marketplace update` refreshes the catalog, `plugin update` actually
re-installs the plugin from it (restart Claude Code to apply). Note the `@skills` suffix on
`plugin update` — without it, Claude Code reports "Plugin not found".

Skills-dir install: `git -C /tmp/skills pull && cp -R /tmp/skills/plugins/i-have-work ~/.claude/skills/i-have-work`.

### Uninstall

```bash
claude plugin uninstall i-have-work
claude plugin marketplace remove skills
```

Skills-dir install: `rm -rf ~/.claude/skills/i-have-work`.

Or keep it installed and just turn it off: `claude plugin disable i-have-work`.

### Always-on (optional, permanent enable)

A `SessionStart` hook loads the full ruleset at the start of every session, no `/i-have-work`
needed:

```bash
touch ~/.claude/.i-have-work-always
```

Turn it back off:

```bash
rm ~/.claude/.i-have-work-always
```

The hook only fires when the flag file exists, so installing the plugin changes nothing by
itself. Honors `$CLAUDE_CONFIG_DIR` if you've moved your config dir. Saying "stop work mode"
still turns it off for just the current session, without touching the flag file.

</details>

<details open>
<summary><strong>Codex</strong></summary>

Codex on this machine resolves skills from `$CODEX_HOME/skills/<name>/SKILL.md` (default
`~/.codex/skills`), and also supports installing skills as plugins through a marketplace. Both
are documented below; the direct copy is the simplest and requires no Codex plugin subsystem.

### Install (direct — simplest, recommended)

```bash
git clone https://git.skea.io/S/skills.git /tmp/skills
mkdir -p ~/.codex/skills
cp -R /tmp/skills/plugins/i-have-work/skills/i-have-work ~/.codex/skills/i-have-work
```

That copies `SKILL.md` and `agents/openai.yaml` together, which is everything Codex needs.

Start a new Codex session, type `$i-have-work`.

### Install (plugin/marketplace route)

```bash
codex plugin marketplace add https://git.skea.io/S/skills.git --ref main
codex plugin add i-have-work@skills
```

Type `$i-have-work` to apply it explicitly.

> **Known limitation — this route currently fails Codex's plugin validation.** Codex's own
> bundled validator (`plugin-creator/scripts/validate_plugin.py`, which its docs describe as
> mirroring the workspace plugin ingestion schema) rejects this plugin with:
>
> ```
> skill `i-have-work` frontmatter field `disable-model-invocation` must be false
> ```
>
> That field is deliberately `true`, because it is Claude Code's mechanism for guaranteeing
> the skill never activates until you invoke it — a core design requirement here. Codex
> expresses the same intent through `policy.allow_implicit_invocation: false` in
> `agents/openai.yaml`, which this skill also sets. The two platforms simply disagree about
> the field, and Claude Code's guarantee wins.
>
> **Use the direct-copy route above for Codex.** It bypasses plugin ingestion entirely and is
> unaffected. If you specifically need the plugin route, delete the
> `disable-model-invocation` line from your local copy of `SKILL.md` — but understand that
> doing so lets Claude Code auto-invoke the skill if you install the same copy there.

> **Verification note:** the `codex plugin ...` command syntax above is taken from Codex's own
> bundled `plugin-creator`/`skill-installer` reference docs and from upstream's
> (`i-have-adhd`) documented usage. It was **never executed live**, because this route fails
> Codex's plugin validation anyway (see above). The direct-copy route is the supported one and
> has been exercised against the real `codex` CLI — see
> [What is actually verified](#what-is-actually-verified).

### Verify

```bash
codex plugin list          # plugin/marketplace route
ls ~/.codex/skills          # direct-copy route: i-have-work/ present
```

### Update

Direct-copy route: re-run the `git clone`/`cp -R` steps above (or `git -C /tmp/skills pull`
first).

Plugin route:

```bash
codex plugin marketplace upgrade skills
codex plugin remove i-have-work
codex plugin add i-have-work@skills
```

### Uninstall

Direct-copy route:

```bash
rm -rf ~/.codex/skills/i-have-work
```

Plugin route:

```bash
codex plugin remove i-have-work
codex plugin marketplace remove skills
```

### Always-on (optional, permanent enable)

Codex loads `AGENTS.md` automatically. This repo ships a script that appends a clearly
marked, idempotent block to `~/.codex/AGENTS.md` — it never touches any of your existing
content in that file:

```bash
sh /tmp/skills/plugins/i-have-work/scripts/codex-enable-always.sh
```

Turn it back off (removes exactly that block, nothing else):

```bash
sh /tmp/skills/plugins/i-have-work/scripts/codex-disable-always.sh
```

Both scripts honor `$CODEX_HOME` if you've moved your config dir, default to
`~/.codex/AGENTS.md`, and are safe to run more than once (the enable script is a no-op if the
block is already present; the disable script is a no-op if it's already absent).

</details>

## How activation works

1. **Installed, not invoked.** Nothing changes until you invoke it, on either platform.
   `SKILL.md` sets `disable-model-invocation: true` (Claude Code's control) and
   `agents/openai.yaml` sets `policy.allow_implicit_invocation: false` (Codex's equivalent).
   Flip the `openai.yaml` value to `true` in your local copy if you *want* Codex to apply this
   discipline on its own.
2. **You type `/i-have-work`** (Claude Code) **or `$i-have-work`** (Codex). Rules apply for
   that session. Say "stop work mode" or "normal mode" to turn them off again.
3. **You turn on permanent mode** — `bash skills.sh enable`, or `--permanent` at install time,
   or manually via `~/.claude/.i-have-work-always` / `codex-enable-always.sh`. Rules apply from
   message one, every session, until you explicitly turn it back off.

In Claude Code, no middle ground: if you didn't turn it on, it's off.

## What is actually verified

Being precise about this, because "it should work" is not verification:

**Verified live, against the real CLI:**

- Claude Code marketplace add / install / list / enable / disable / update / uninstall /
  marketplace remove, including installing from the live Gitea URL.
- `claude plugin validate` on both the plugin and marketplace manifests.
- The `SessionStart` always-on hook: silent without the flag file, emits the ruleset with it,
  silent again after removal.
- The Codex `AGENTS.md` enable/disable scripts: idempotent, preserve pre-existing user
  content, remove only their own managed block.

**Verified by automated test with mocked CLIs, in a fully isolated sandbox:**

- The whole `skills.sh` lifecycle: install, update, enable, disable, uninstall, status,
  doctor; idempotency; argument validation and conflicts; platform auto-detection and explicit
  selection; source selection and fallback; the interactive prompt (using a real pty, defaulting
  to No); Codex atomic replace with rollback and no leftover staging/backup directories; not
  touching other skills, other plugins, or `auth.json`; and paths containing spaces.
- Tests run with `HOME`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR` and `PATH` all redirected into a
  temporary sandbox, so they never read or modify a real `~/.claude` or `~/.codex`.

**Partially verified against the real Codex CLI (codex-cli 0.145.0):**

- The CLI is detected correctly when installed as a standalone outside `PATH`
  (`~/.local/bin/codex` → `~/.codex/packages/standalone/...`).
- `skills.sh install --codex` deploys `SKILL.md` and `agents/openai.yaml` into
  `$CODEX_HOME/skills/i-have-work/`, and the real `codex doctor` reads that same `CODEX_HOME`
  without complaint.

**Not verified live:**

- **Actual `$i-have-work` invocation inside a Codex session.** Driving a real Codex session
  requires authentication, which is out of scope for an automated test suite, so the skill's
  runtime behavior in Codex is unconfirmed. The install layout is correct and the CLI accepts
  it; what has not been observed is Codex loading and applying the skill in a live session.
- **The Codex plugin/marketplace route**, which is rejected by Codex's plugin validator (see
  the known-limitation note above). The direct-copy route used by `skills.sh` is unaffected.

## Troubleshooting

**`/i-have-work` not in autocomplete.** Restart Claude Code — the plugin index is read at
startup.

**Always-on flag has no effect.** Confirm the plugin actually ships `hooks/hooks.json`
(`claude plugin details i-have-work` should list `Hooks (1) SessionStart`), then restart.

**`claude plugin marketplace add` fails.** Use the full git URL
(`https://git.skea.io/S/skills.git`) or a local path pointing at the repo root, not at
`.claude-plugin/`.

**Codex `AGENTS.md` block didn't apply.** Confirm `$CODEX_HOME` (or `~/.codex`) is the config
dir Codex is actually reading on your machine, and that you started a new session after
running the enable script.

**Installed but replies still ignore the discipline.** Open a new session/thread. If it still
drifts, tighten the wording in `plugins/i-have-work/skills/i-have-work/SKILL.md`.
