# Install i-have-work

Authoritative source: `https://git.skea.io/S/skills` (Gitea). GitHub, if configured, is a
read-only mirror only — see [NOTICE.md](./NOTICE.md).

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
cp -R /tmp/skills/plugins/i-have-work/skills/i-have-work/agents ~/.codex/skills/i-have-work/agents 2>/dev/null || true
```

(The `agents/openai.yaml` file travels with the skill folder already; the second line is a
no-op safety net if you copy files individually instead of the whole directory.)

Start a new Codex session, type `$i-have-work`.

### Install (plugin/marketplace route)

```bash
codex plugin marketplace add https://git.skea.io/S/skills.git --ref main
codex plugin add i-have-work@skills
```

Type `$i-have-work` to apply it explicitly. Codex also allows implicit invocation
(`policy.allow_implicit_invocation: true` in `agents/openai.yaml`), so Codex may apply it on
its own when it judges a task calls for this discipline.

> **Verification note:** the `codex` CLI was not present on the machine this repo was built
> and tested on, so the `codex plugin ...` command syntax above is taken from Codex's own
> bundled `plugin-creator`/`skill-installer` reference docs and from upstream's
> (`i-have-adhd`) documented usage, not from a live end-to-end run. The direct-copy method
> above **was** verified structurally against Codex's real, currently-installed
> `skill-installer` skill, which confirms `$CODEX_HOME/skills/<name>/SKILL.md` as the actual
> install target. Treat the plugin/marketplace route as documented-but-unexecuted until you
> confirm it on a machine with `codex` on `PATH`.

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

1. **Installed, not invoked.** `SKILL.md` sets `disable-model-invocation: true` for Claude
   Code, so nothing changes until you invoke it. Codex ships with implicit invocation allowed
   by default (see `agents/openai.yaml`), so it may apply the skill on its own when relevant —
   turn that off by editing `policy.allow_implicit_invocation` to `false` in your local copy if
   you don't want that.
2. **You type `/i-have-work`** (Claude Code) **or `$i-have-work`** (Codex). Rules apply for
   that session. Say "stop work mode" or "normal mode" to turn them off again.
3. **You touch `~/.claude/.i-have-work-always`** (Claude Code) or **run
   `codex-enable-always.sh`** (Codex). Rules apply from message one, every session, until you
   explicitly turn it back off.

In Claude Code, no middle ground: if you didn't turn it on, it's off.

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
