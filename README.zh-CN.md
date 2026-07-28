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

> **Gitea 是唯一权威源，GitHub 仅作为公开只读镜像。**
> 所有开发、提交、Tag 与发布都在 [`git.skea.io/S/skills`](https://git.skea.io/S/skills) 进行；
> [`github.com/eynov/skills`](https://github.com/eynov/skills) 由 Gitea Push Mirror 自动同步，
> 直接推送到 GitHub 的改动会在下次同步时被覆盖。
> 详见 [NOTICE.md](./NOTICE.md)（英文，含托管关系与 attribution 说明）。

## 安装

从 GitHub 安装：

```bash
git clone https://github.com/eynov/skills.git
cd skills
bash install.sh
```

从 Gitea 安装：

```bash
git clone https://git.skea.io/S/skills.git
cd skills
bash install.sh
```

就这么简单。安装器会自动检测你装了哪些 Agent（Claude Code、Codex，或两者），并分别安装。
它不会替你安装任何 CLI，也不会在你没要求的情况下开启永久模式。

然后新开一个会话，调用一次：

| Agent | 调用方式 |
|---|---|
| Claude Code | `/i-have-work` |
| Codex | `$i-have-work` |

## 日常管理

`skills.sh` 是唯一入口，所有操作都通过它完成。（`install.sh` 只是 `skills.sh install` 的快捷方式。）

```bash
bash skills.sh install      # 为检测到的 Agent 安装
bash skills.sh update       # 用当前仓库的版本重新部署
bash skills.sh status       # 查看安装与启用状态
bash skills.sh doctor       # 诊断
bash skills.sh enable       # 开启永久模式
bash skills.sh disable      # 关闭永久模式
bash skills.sh uninstall    # 卸载
bash skills.sh help         # 完整用法
```

所有命令都支持 `--claude`、`--codex`、`--all` 来指定目标平台。
不写平台参数时自动检测；但**显式指定的平台绝不会被静默跳过**（找不到就明确报错）。

常用组合：

```bash
bash skills.sh install --all --permanent      # 安装并开启永久模式
bash skills.sh install --all --no-permanent   # 安装但保持按需调用（默认）
bash skills.sh install --source github        # 强制用 GitHub 镜像作为插件源
bash skills.sh uninstall --claude --remove-marketplace
```

所有操作都是幂等的，重复执行安全。

## 日常维护

查看安装状态（以及是否与当前仓库一致）：

```bash
bash skills.sh status
```

环境检查（CLI、清单文件、权限、残留、远端可达性）：

```bash
bash skills.sh doctor
```

运行本仓库的完整测试：

```bash
bash skills.sh self-test
```

更新到新版本 —— 先拉取，再重新部署：

```bash
git pull --ff-only
bash skills.sh update
```

`status` 会显示当前部署的版本，以及它是否仍与仓库一致：

| 状态 | 含义 |
|---|---|
| `Up to date` | 已安装的副本与当前仓库一致 |
| `Update available` | 已安装的副本与仓库不同 —— 执行 `skills.sh update` |
| `Unknown` | 无法读取或无法比较，**不猜测** |
| `External install` | 由本仓库以外的方式安装（手动安装或其他 checkout） |

`status` 与 `doctor` 都是严格只读的，不会修改任何文件。

## 默认按需启用（opt-in）

**安装本身不会改变 Agent 的任何行为。** 在你主动调用之前，Skill 始终处于未激活状态，
两个平台都是如此：

- **Claude Code** — `SKILL.md` 中 `disable-model-invocation: true`
- **Codex** — `agents/openai.yaml` 中 `policy.allow_implicit_invocation: false`

**永久模式是一个独立的、需要你主动做出的选择。**
用 `bash skills.sh enable`（或安装时加 `--permanent`）开启后，每个新会话从第一条消息起自动生效。
用 `bash skills.sh disable` 关闭，Skill 本身仍然保持安装状态，不会被卸载。
如果只想在当前会话临时关闭，直接对 Agent 说「stop work mode」即可。

如果你在**交互式终端**里执行 `install` 且没写 `--permanent` / `--no-permanent`，
会询问你一次，**默认答案是 No**。
在脚本或 CI 等非交互环境中，不会询问、不会卡住等待输入，也不会开启永久模式。

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

## 说明与已知限制

- **`update` 部署的是当前仓库里的内容，不会自动拉取远程更新。**
  这是有意设计：仓库可能来自 Gitea clone、GitHub clone、ZIP 解压包，或只读挂载。
  想获取新版本，请你自己先更新仓库（例如 `git pull`），再执行 `bash skills.sh update`。
- **Codex 使用「直接复制」路线，不使用 plugin/marketplace 路线。**
  因为 Codex 的插件校验器会拒绝 `disable-model-invocation: true`，
  而这个字段正是 Claude Code 用来保证「不调用就不生效」的机制，必须保留。
  这是一个已知并已记录的跨平台字段冲突，详见 [INSTALL.md](./INSTALL.md)。
- **Codex 侧属于「部分验证」。**
  安装流程已用**真实的 `codex` CLI（0.145.0）**验证过：能正确识别不在 `PATH` 中的
  standalone 安装路径，部署后的 Skill 目录也确实位于真实 `codex doctor` 读取的
  `CODEX_HOME` 位置。
  **尚未验证的是**：在真实 Codex 会话中 `$i-have-work` 实际被加载并生效的运行时行为——
  这需要登录认证，不在自动化测试范围内。
  Claude Code 侧则已用真实 CLI 做过完整的端到端验证。

两个平台完整的安装、验证、更新与卸载说明见 [INSTALL.md](./INSTALL.md)。

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
