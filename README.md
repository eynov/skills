<p align="center">
  <strong>eynov/skills</strong> — Agent Skills for Claude Code and Codex
</p>
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License"></a>
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

> **Gitea is the authoritative source. GitHub is a read-only public mirror.**
> Development happens on [`git.skea.io/S/skills`](https://git.skea.io/S/skills);
> [`github.com/eynov/skills`](https://github.com/eynov/skills) is kept in sync by a Gitea push
> mirror and any change pushed there directly will be overwritten. See
> [NOTICE.md](./NOTICE.md) for hosting and attribution details.

## Install

From GitHub:

```bash
git clone https://github.com/eynov/skills.git
cd skills
bash install.sh
```

From Gitea:

```bash
git clone https://git.skea.io/S/skills.git
cd skills
bash install.sh
```

That's it. The installer detects which agents you have (Claude Code, Codex, or both) and
installs the skill for each. It never installs a CLI for you, and it never turns anything on
permanently unless you ask.

Then invoke it once, in a new session:

| Agent | Invoke |
|---|---|
| Claude Code | `/i-have-work` |
| Codex | `$i-have-work` |

## Managing it

`skills.sh` is the single entry point for everything. (`install.sh` is just a shorthand for
`skills.sh install`.)

```bash
bash skills.sh install      # install for detected agents
bash skills.sh update       # redeploy this repo's version
bash skills.sh status       # what's installed and enabled
bash skills.sh doctor       # diagnostics
bash skills.sh enable       # turn on permanent mode
bash skills.sh disable      # turn off permanent mode
bash skills.sh uninstall    # remove the skill
bash skills.sh help         # full usage
```

Every command accepts `--claude`, `--codex`, or `--all` to target one or both agents. Omit it
and the tool auto-detects — but a platform you name explicitly is never silently skipped.

Useful variations:

```bash
bash skills.sh install --all --permanent      # install and turn on for every session
bash skills.sh install --all --no-permanent   # install, stay on-demand (the default)
bash skills.sh install --source github        # force the mirror as the plugin source
bash skills.sh uninstall --claude --remove-marketplace
```

Everything is idempotent — running any command twice is safe.

## Maintenance

Check what's installed and whether it matches this checkout:

```bash
bash skills.sh status
```

Check the environment (CLIs, manifests, permissions, leftovers, remotes):

```bash
bash skills.sh doctor
```

Run the full test suite against this checkout:

```bash
bash skills.sh self-test
```

Update to a newer version — fetch first, then redeploy:

```bash
git pull --ff-only
bash skills.sh update
```

`status` tells you which revision is deployed and whether it still matches the repo:

| Status | Meaning |
|---|---|
| `Up to date` | The installed copy matches this checkout |
| `Update available` | The installed copy differs — run `skills.sh update` |
| `Unknown` | The installed copy can't be read or compared |
| `External install` | Installed by something other than this checkout |

`status` and `doctor` are strictly read-only and never modify anything.

## On-demand by default

Installing changes nothing on its own. The skill stays inert until you invoke it, on both
agents:

- **Claude Code** — `SKILL.md` sets `disable-model-invocation: true`
- **Codex** — `agents/openai.yaml` sets `policy.allow_implicit_invocation: false`

**Permanent mode** is a separate, explicit choice. Turn it on with `bash skills.sh enable` (or
`--permanent` at install time) and the ruleset applies from the first message of every new
session. `bash skills.sh disable` turns it back off without uninstalling anything. Within a
single session you can also just say "stop work mode".

If you run `install` in an interactive terminal without `--permanent` or `--no-permanent`,
you'll be asked once. The default answer is **No**. In a script or CI, it's never asked and
never enabled.

## What's in this repo

| Skill | What it does |
|---|---|
| [`i-have-work`](plugins/i-have-work/skills/i-have-work/SKILL.md) | Careful, closed-loop production-engineer discipline: confirm the authoritative source, root-cause first, minimal reversible changes, real verification, clean teardown, honest reporting. |

More skills may be added over time under `plugins/<name>/`.

## What `i-have-work` changes

It grants no new tools or permissions. It changes execution discipline:

1. Establish the task boundary and the authoritative source before touching anything.
2. Investigate root cause before changing anything.
3. Change the minimum, keep it reversible.
4. Verify with real execution — an exit code of 0 is not proof of anything.
5. Clean up every temp file, process, port, and rule the task created.
6. For git work: check the full diff, verify local/remote SHAs, confirm a clean tree.
7. Close with an honest, auditable Final Review Pack — unverified stays labeled unverified.

Full ruleset: [`SKILL.md`](plugins/i-have-work/skills/i-have-work/SKILL.md).

## Notes and limitations

- **`update` deploys what is in this repository.** It deliberately never runs `git pull`, so
  it works from a Gitea clone, a GitHub clone, a ZIP export, or a read-only mount. To get newer
  content, update the repo yourself first, then run `bash skills.sh update`.
- **Codex uses the direct-copy route**, not the plugin/marketplace route. Codex's plugin
  validator rejects `disable-model-invocation: true`, which is Claude Code's opt-in guarantee
  and stays. This is a documented cross-platform conflict — details in
  [INSTALL.md](./INSTALL.md).
- **Codex is only partially verified.** Installation was exercised against the real `codex`
  CLI (0.145.0): standalone-path detection works, and the deployed skill lands where `codex
  doctor` expects it. What has *not* been observed is `$i-have-work` actually firing inside a
  live Codex session, since that needs authentication. Claude Code, by contrast, is verified
  end-to-end against the real CLI.

Full install, verification, update and uninstall detail for both agents:
[INSTALL.md](./INSTALL.md).

## Relationship to `i-have-adhd`

`i-have-work` reuses the install/plugin/hook architecture proven by
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT licensed), with all new
persona and workflow content written for this project. See [NOTICE.md](./NOTICE.md) for the
full breakdown of what was reused vs. original, and licensing/attribution.

## License

MIT — see [LICENSE](./LICENSE) and [NOTICE.md](./NOTICE.md).
