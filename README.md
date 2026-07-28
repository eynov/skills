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

> **Gitea is the authoritative source. GitHub, if configured, is a read-only public mirror
> only.** See [NOTICE.md](./NOTICE.md) for hosting and attribution details.

## Install

<details>
<summary><strong>Claude Code</strong></summary>

```bash
claude plugin marketplace add https://git.skea.io/S/skills.git
claude plugin install i-have-work@skills
```

Then type `/i-have-work`. Want it on every session? `touch ~/.claude/.i-have-work-always`
(see [INSTALL.md](./INSTALL.md)).

</details>

<details>
<summary><strong>Codex</strong></summary>

```bash
git clone https://git.skea.io/S/skills.git /tmp/skills
mkdir -p ~/.codex/skills
cp -R /tmp/skills/plugins/i-have-work/skills/i-have-work ~/.codex/skills/i-have-work
```

Then type `$i-have-work`. Full details, including the plugin/marketplace route and the
always-on `AGENTS.md` script, in [INSTALL.md](./INSTALL.md).

</details>

## What's in this repo

| Skill | What it does |
|---|---|
| [`i-have-work`](plugins/i-have-work/skills/i-have-work/SKILL.md) | Careful, closed-loop production-engineer discipline: confirm the authoritative source, root-cause first, minimal reversible changes, real verification, clean teardown, honest reporting. |

More skills may be added to this repo over time under `plugins/<name>/`.

## What `i-have-work` changes

It does not grant new tools or permissions. It changes execution discipline:

1. Establish the task boundary and the authoritative source before touching anything.
2. Investigate root cause before changing anything.
3. Change the minimum, keep it reversible.
4. Verify with real execution — an exit code of 0 is not proof of anything.
5. Clean up every temp file, process, port, and rule the task created.
6. For git work: check the full diff, verify local/remote SHAs, confirm a clean tree.
7. Close with an honest, auditable Final Review Pack — unverified stays labeled unverified.

Full ruleset: [`SKILL.md`](plugins/i-have-work/skills/i-have-work/SKILL.md).

## Relationship to `i-have-adhd`

`i-have-work` reuses the install/plugin/hook architecture proven by
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT licensed), with all new
persona and workflow content written for this project. See [NOTICE.md](./NOTICE.md) for the
full breakdown of what was reused vs. original, and licensing/attribution.

## License

MIT — see [LICENSE](./LICENSE) and [NOTICE.md](./NOTICE.md).
