#!/usr/bin/env bash
# Guards the core design promise: i-have-work must never change agent behavior
# until it is explicitly invoked. Each platform enforces that with its own
# control, and both must stay set:
#
#   Claude Code -> SKILL.md      frontmatter `disable-model-invocation: true`
#   Codex       -> openai.yaml   `policy.allow_implicit_invocation: false`
#
# Also validates that SKILL.md frontmatter and openai.yaml are parseable YAML
# and that the skill name matches its directory.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
skill_dir="$repo_root/plugins/i-have-work/skills/i-have-work"
skill_md="$skill_dir/SKILL.md"
openai_yaml="$skill_dir/agents/openai.yaml"
fail=0

for f in "$skill_md" "$openai_yaml"; do
  if [ ! -f "$f" ]; then
    echo "FAIL missing required file: $f"
    exit 1
  fi
done

# SKILL.md frontmatter: valid YAML, correct name, model invocation disabled.
if python3 - "$skill_md" <<'PY'
import sys, yaml
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if not text.startswith("---"):
    sys.exit("no YAML frontmatter block")
end = text.find("\n---", 3)
if end == -1:
    sys.exit("unterminated YAML frontmatter block")
fm = yaml.safe_load(text[3:end])
assert fm.get("name") == "i-have-work", f"name is {fm.get('name')!r}, expected 'i-have-work'"
assert fm.get("disable-model-invocation") is True, \
    "disable-model-invocation must be true (Claude Code opt-in guarantee)"
assert fm.get("description"), "description must be non-empty"
PY
then
  echo "OK   SKILL.md frontmatter valid, name matches, model-invocation disabled"
else
  echo "FAIL SKILL.md frontmatter check"
  fail=1
fi

# openai.yaml: valid YAML, implicit invocation disabled.
if python3 - "$openai_yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
policy = data.get("policy") or {}
assert policy.get("allow_implicit_invocation") is False, \
    "policy.allow_implicit_invocation must be false (Codex opt-in guarantee)"
assert (data.get("interface") or {}).get("display_name"), "interface.display_name required"
PY
then
  echo "OK   openai.yaml valid, implicit invocation disabled"
else
  echo "FAIL openai.yaml check"
  fail=1
fi

# Skill directory name must match the declared skill name.
if [ "$(basename "$skill_dir")" = "i-have-work" ]; then
  echo "OK   skill directory name matches skill name"
else
  echo "FAIL skill directory name does not match skill name"
  fail=1
fi

exit "$fail"
