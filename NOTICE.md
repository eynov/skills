# Notice / Attribution

## Relationship to `i-have-adhd`

`i-have-work` (this repository, `S/skills` on Gitea) is a new, independent skill inspired by and
architecturally adapted from **[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)** by
Ayoub Ghriss (MIT licensed).

What was reused from upstream, near-verbatim, because it already works well:

- The overall shape of a "persistent output/behavior skill": a `SKILL.md` with
  `disable-model-invocation: true`, an explicit on-demand invocation, and a separate,
  toggleable always-on path.
- The Claude Code always-on mechanism: a `SessionStart` hook (`hooks/hooks.json`,
  `hooks/always-on.sh`) that only injects the ruleset when a flag file exists, fails open
  (never blocks session start), and is pure POSIX `sh`.
- The `.claude-plugin/plugin.json` / `.claude-plugin/marketplace.json` and
  `.codex-plugin/plugin.json` / `.agents/plugins/marketplace.json` manifest shapes, and the general
  install / verify / update / uninstall documentation structure in `INSTALL.md`.

What is original to this repository:

- The entire persona and workflow content of `i-have-work` — the production-engineering
  discipline, the standard execution flow, the Final Review Pack format — is new content
  written for this project, not a renamed copy of the ADHD-focused ruleset.
- The Codex always-on mechanism (`scripts/codex-enable-always.sh` /
  `codex-disable-always.sh`, a managed block in `AGENTS.md`) is new: upstream's Codex
  always-on instructions are documentation-only (a snippet the user pastes by hand). This
  repo scripts that same idea safely and idempotently.
- The repository layout (`plugins/<name>/` with a repo-root marketplace, anticipating more
  than one skill over time) is new; upstream is a single-plugin repository.

## License

Both the reused architecture and the original content are distributed under the MIT License
(see `LICENSE`), preserving the required upstream copyright notice.

## Hosting

- **Gitea** (`https://git.skea.io/S/skills`) is the authoritative source for this repository.
- **GitHub** ([`eynov/skills`](https://github.com/eynov/skills)) is a read-only public mirror,
  kept in sync by a Gitea push mirror. Do not commit or open PRs there — changes made on
  GitHub are overwritten on the next sync.
- `upstream` (`https://github.com/ayghri/i-have-adhd.git`) is kept as a git remote for
  reference only — nothing is pushed to it, and it is not this project's origin.

This project is not a GitHub "fork" in the platform sense and does not claim to be the
original author's work. If you want the original ADHD-focused skill, use
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) directly.
