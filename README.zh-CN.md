<p align="center">
  <strong>eynov/skills</strong> — 面向 Claude Code 与 Codex 的 Agent Skills 仓库
</p>
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="许可证"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <strong>简体中文</strong>
</p>

> **Gitea 是唯一权威源，GitHub（如已配置）仅作为公开只读镜像。**
> 详见 [NOTICE.md](./NOTICE.md)（英文，含托管关系与 attribution 说明）。

- 权威仓库（Gitea）：`https://git.skea.io/S/skills`
- 本地长期工作树：`/opt/skills`
- 上游参考项目：[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)（仅作参考，不 push）

## 这个仓库里有什么

| Skill | 作用 |
|---|---|
| [`i-have-work`](plugins/i-have-work/skills/i-have-work/SKILL.md) | 让 Agent 表现得像谨慎、可靠、能把任务真正闭环的高级工程师/生产运维负责人：先确认权威配置源，定位根因，做最小可回滚修改，进行真实验证，清理残留，诚实汇报。 |

未来该仓库还会在 `plugins/<name>/` 下加入其他 Skill。

## `i-have-work` 改变了什么

**不会**改变 Agent 的工具权限，也不会凭空增加能力。它只改变执行纪律：

1. 动手前先确认任务边界和权威持久配置源（不是部署副本、生成文件、镜像或临时目录）。
2. 修改前先调查根因，不靠猜测。
3. 只做必要的最小修改，且可回滚。
4. 用真实运行结果验证，命令返回 0 不等于任务完成。
5. 清理本任务产生的所有临时文件、进程、端口、规则等残留。
6. Git 任务：检查完整 diff，push 后核实本地/远端 commit SHA 一致，确认工作树 clean。
7. 收尾时给出诚实、可审计的 Final Review Pack；未验证的内容明确标注，不伪造结果。

完整规则见 [`SKILL.md`](plugins/i-have-work/skills/i-have-work/SKILL.md)（英文原文，是 Agent 实际读取执行的内容）。

## 安装与使用

### Claude Code

**安装（Marketplace 方式）：**

```bash
claude plugin marketplace add https://git.skea.io/S/skills.git
claude plugin install i-have-work@skills
```

**当前会话手动启用：** 输入 `/i-have-work`。

**验证安装：**

```bash
claude plugin list
```

应看到 `i-have-work@skills` 状态为 `✔ enabled`。

**永久启用（每次新会话自动生效）：**

```bash
touch ~/.claude/.i-have-work-always
```

原理：插件自带一个 `SessionStart` 钩子，只有在这个标记文件存在时才会在会话开始时注入完整规则；不加这个文件，装了插件也不会自动改变行为。

**取消永久启用：**

```bash
rm ~/.claude/.i-have-work-always
```

**当前会话临时关闭：** 直接对 Claude 说“stop work mode”（或“normal mode”），只影响本次会话，不影响永久启用标记。

**卸载：**

```bash
claude plugin uninstall i-have-work
claude plugin marketplace remove skills
```

**不想用 marketplace？** 也可以直接把插件目录复制进个人 Skills 目录，无需 marketplace：

```bash
git clone https://git.skea.io/S/skills.git /tmp/skills
cp -R /tmp/skills/plugins/i-have-work ~/.claude/skills/i-have-work
```

下次会话会自动加载为 `i-have-work@skills-dir`；当前会话执行 `/reload-plugins` 可立即加载。

### Codex

Codex 会从 `$CODEX_HOME/skills/<name>/SKILL.md`（默认 `~/.codex/skills`）读取 Skill，这是本机上经过核实的真实机制。

**安装（推荐，直接复制）：**

```bash
git clone https://git.skea.io/S/skills.git /tmp/skills
mkdir -p ~/.codex/skills
cp -R /tmp/skills/plugins/i-have-work/skills/i-have-work ~/.codex/skills/i-have-work
```

**当前会话手动启用：** 新开一个 Codex 会话，输入 `$i-have-work`。

**验证安装：**

```bash
ls ~/.codex/skills
```

能看到 `i-have-work` 目录即为安装成功。

**永久启用（每次新会话自动生效）：**

```bash
sh /tmp/skills/plugins/i-have-work/scripts/codex-enable-always.sh
```

原理：这个脚本会在 `~/.codex/AGENTS.md` 中追加一段**有明确起止标记、可安全重复执行**的规则块；如果你已经有自己的 `AGENTS.md` 内容，脚本只会追加，不会修改或覆盖原有内容。Codex 每次会话都会读取 `AGENTS.md`，因此这段规则会自动生效。

**取消永久启用：**

```bash
sh /tmp/skills/plugins/i-have-work/scripts/codex-disable-always.sh
```

这个脚本只会删除它自己添加的那一段（由起止标记界定），不会动你 `AGENTS.md` 里的其他内容。

**卸载：**

```bash
rm -rf ~/.codex/skills/i-have-work
```

**关于 Codex 的插件/市场方式：** 本仓库同时提供了 `.codex-plugin/plugin.json` 与
`.agents/plugins/marketplace.json`，理论上可以用
`codex plugin marketplace add https://git.skea.io/S/skills.git --ref main` +
`codex plugin add i-have-work@skills` 安装。**但这条路径在实现本项目时未能用真实的
`codex` 命令行验证**（构建环境里没有 `codex` 可执行文件），仅依据 Codex 自带的
`plugin-creator`/`skill-installer` 系统 Skill 文档整理而来。上面“直接复制”的方式已经
对照 Codex 真实的 `skill-installer` 目标目录结构核实过，请优先使用。

## 与 `i-have-adhd` 的关系

`i-have-work` 复用了 [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)（MIT 许可）
已经验证成熟的安装/插件/Hook 架构（marketplace 结构、SessionStart 常驻钩子模式、
`disable-model-invocation` 的按需调用模型等），但 Skill 本身的人格与工作流程内容是
完全为本项目重新编写的原创内容，不是简单改名。完整的复用范围说明、许可证与
attribution 见 [NOTICE.md](./NOTICE.md)（英文）。

本项目不是 GitHub 平台意义上的 Fork，也不冒充原作者；如果你需要原始的 ADHD 输出风格
Skill，请直接使用 [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)。

## 许可证

MIT，详见 [LICENSE](./LICENSE) 与 [NOTICE.md](./NOTICE.md)。
