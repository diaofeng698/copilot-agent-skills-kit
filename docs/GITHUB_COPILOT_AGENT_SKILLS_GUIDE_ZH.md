# GitHub Copilot + agent-skills 从零开始指南

本手册面向第一次使用 `agent-skills` 的 GitHub Copilot 用户，覆盖：

1. 从零创建或打开一个 VS Code 工作空间；
2. 安装项目级 Agent Skills；
3. 安装代码审查、测试、安全和性能 Persona；
4. 配置项目级 Copilot Instructions；
5. 从需求、计划、实现、测试、审查走到发布；
6. 安装和使用独立 `copilot` CLI；
7. 更新、卸载与常见问题排查。

本文以 Linux/Remote SSH 为主要示例，内容基于 2026-09-18 的官方文档和
`agent-skills v0.6.10`。

> 本维护仓库通过 Git submodule 固定第三方 `agent-skills` 版本，并提供经过测试的
> 安装、更新和验证脚本。新电脑或新项目优先使用第 0 节；第 2 至 6 节保留为理解
> 原理和手动安装时的参考。

---

## 0. 使用维护仓库快速配置

### 0.1 在新电脑克隆

将 `<repository-url>` 替换为本维护仓库发布后的地址：

```bash
git clone --recurse-submodules <repository-url> copilot-agent-skills-kit
cd copilot-agent-skills-kit
./scripts/verify.sh
```

如果克隆时忘记使用 `--recurse-submodules`：

```bash
git submodule update --init --recursive
```

### 0.2 预览并安装到项目

目标项目目录必须已经存在。先运行 dry-run：

```bash
./scripts/install.sh --target /path/to/my-project --dry-run
```

确认输出后执行安装：

```bash
./scripts/install.sh --target /path/to/my-project
./scripts/verify.sh --target /path/to/my-project
```

安装器会部署：

- `.agents/skills/` 下的全部上游 Skill；
- `.agents/references/` 下的共享检查清单；
- `.github/agents/` 下使用 `.agent.md` 后缀的专业 Persona；
- 记录固定上游提交的 `.agent-skills-kit.lock`。

如果目标项目尚无 `.github/copilot-instructions.md`，安装器还会复制维护仓库提供的
模板；已有文件默认保留。只有明确希望替换时才使用：

```bash
./scripts/install.sh \
  --target /path/to/my-project \
  --force-instructions
```

如果目标项目已有与上游同名、但不属于本工具包管理的 Skill、参考资料或 Persona，
安装会在任何写入前停止。审阅 dry-run 和现有内容，确认要交给工具包管理后才使用：

```bash
./scripts/install.sh \
  --target /path/to/my-project \
  --force-managed
```

### 0.3 安装后的 VS Code 操作

1. 用 VS Code 打开目标项目根目录；
2. 运行 **Developer: Reload Window**；
3. 新建 Copilot Chat 会话；
4. 使用 `/skills` 和 `/agents` 检查发现状态；
5. 从 `/spec-driven-development` 或其他与任务匹配的 Skill 开始。

---

## 1. 四个核心概念

| 概念 | 作用 | 项目级位置 |
| --- | --- | --- |
| Skill | 描述“怎样完成某类任务”的工作流 | `.agents/skills/<name>/SKILL.md` |
| Persona | 让 Copilot 以特定专业角色工作 | `.github/agents/*.agent.md` |
| Custom Instructions | 对当前项目始终生效的简短规则 | `.github/copilot-instructions.md` |
| CLI Plugin | 为独立 Copilot CLI 打包安装整套技能 | 用户 Copilot 配置目录 |

Skill 会按需加载。安装全部技能不会让 Copilot 在每次对话中加载全部正文；它先
读取 Skill 的名称和描述，只在任务匹配时加载详细流程。

Persona 回答“由谁来做”，Skill 回答“怎样做”。例如 `code-reviewer` 是代码审查
角色，`code-review-and-quality` 是它应遵循的审查流程。

---

## 2. 准备环境

### 2.1 必备条件

- 有效的 GitHub Copilot 订阅；
- 已登录 GitHub 的较新版 VS Code；
- 已启用 GitHub Copilot/Chat；
- Git；
- 能访问 GitHub；
- Node.js 22.20 或更高版本，用于运行当前 `skills` CLI 或通过 npm 安装
  Copilot CLI。

检查环境：

```bash
git --version
node --version
npm --version
```

如果 Node.js 低于 22.20，推荐通过已有版本管理器升级。例如使用 `nvm`：

```bash
nvm install 22
nvm use 22
node --version
```

### 2.2 Remote SSH 用户

通过 VS Code Remote SSH 工作时，Git、Node.js、技能文件和 Copilot CLI 都应位于
远程主机。确认 VS Code 左下角显示远程连接，并在远程终端执行本手册命令。

---

## 3. 从零创建工作空间

创建一个名为 `my-project` 的项目：

```bash
mkdir -p ~/workspace/my-project
cd ~/workspace/my-project
git init
code .
```

也可以在 VS Code 中选择 **File → Open Folder** 打开该目录。

如果使用已有项目，不要再次执行 `git init`，直接打开其 Git 根目录。可用以下命令
确认根目录：

```bash
git rev-parse --show-toplevel
```

建议始终从项目根目录安装，否则 Copilot 可能无法在整个项目范围发现配置。

---

## 4. 安装 VS Code Copilot 项目级技能

### 4.1 安装前审阅

第三方 Skill 可能包含脚本或工具调用。先查看可用技能：

```bash
npx skills add addyosmani/agent-skills --list
```

安装前应审阅 `SKILL.md`、引用的脚本和外部地址。不要为未审阅的 Skill 预先开放
不受限制的 Shell 权限。

### 4.2 安装全部技能

在项目根目录执行：

```bash
npx skills add addyosmani/agent-skills \
  --agent github-copilot \
  --skill '*' \
  --copy \
  --yes
```

安装后会出现类似结构：

```text
my-project/
├── .agents/
│   └── skills/
│       ├── using-agent-skills/
│       │   └── SKILL.md
│       ├── spec-driven-development/
│       │   └── SKILL.md
│       └── ...
└── skills-lock.json
```

`.agents/skills/` 是 Copilot 官方支持的项目级 Skill 目录之一；另外也支持
`.github/skills/` 和 `.claude/skills/`。同一 Skill 不要重复放入多个项目目录。

只想从最核心的三个 Skill 开始时：

```bash
npx skills add addyosmani/agent-skills \
  --agent github-copilot \
  --skill spec-driven-development test-driven-development code-review-and-quality \
  --copy \
  --yes
```

### 4.3 从本地克隆安装

需要完整审阅、保留共享参考资料或自行修改时，先把源仓库放到稳定目录：

```bash
mkdir -p ~/.local/share
git clone https://github.com/addyosmani/agent-skills.git \
  ~/.local/share/agent-skills
```

然后在项目根目录安装：

```bash
npx skills add ~/.local/share/agent-skills \
  --agent github-copilot \
  --skill '*' \
  --copy \
  --yes
```

### 4.4 安装共享参考清单

部分 Skill 会引用源仓库顶层 `references/`。安装器会复制 Skill 自身资源，但不一定
复制跨 Skill 的共享文件。使用本地克隆时执行：

```bash
mkdir -p .agents/references
cp -R ~/.local/share/agent-skills/references/. .agents/references/
```

这样 Skill 中的 `../../references/` 会正确指向 `.agents/references/`。

---

## 5. 安装四个专业 Persona

工作空间 Persona 放在 `.github/agents/`，文件必须使用 `.agent.md` 后缀。源仓库
中的文件是普通 `.md`，复制时要重命名。

如果尚未克隆源仓库，先执行第 4.3 节。然后在项目根目录执行：

```bash
mkdir -p .github/agents

for name in \
  code-reviewer \
  test-engineer \
  security-auditor \
  web-performance-auditor
do
  cp ~/.local/share/agent-skills/agents/${name}.md \
    .github/agents/${name}.agent.md
done
```

| Persona | 使用场景 |
| --- | --- |
| `code-reviewer` | 合并前进行正确性、可读性、架构、安全和性能审查 |
| `test-engineer` | 设计测试策略、检查覆盖缺口、为缺陷编写复现测试 |
| `security-auditor` | 威胁建模、OWASP 检查和漏洞审计 |
| `web-performance-auditor` | Web 性能和 Core Web Vitals 审计 |

在 VS Code Chat 的 Agent 选择器中选择角色。输入 `/agents` 可以打开
**Configure Custom Agents** 检查发现状态。

Persona 不应调用另一个 Persona。需要多角色审查时，由用户或主 Agent 并行发起，
最后汇总结论。

---

## 6. 添加项目级 Copilot Instructions

创建 `.github/copilot-instructions.md`。这里只放几乎每个任务都适用的简短规则，
不要粘贴所有 Skill 全文，否则会浪费上下文并破坏按需加载。

可使用以下模板：

```markdown
# Project Copilot Instructions

## Skill routing
- Start by considering the `using-agent-skills` skill.
- New features: use `spec-driven-development`, then
  `planning-and-task-breakdown`.
- Implementation: use `incremental-implementation` and
  `test-driven-development`.
- Bugs: use `debugging-and-error-recovery`; reproduce first.
- Before merge: use `code-review-and-quality`.
- Before release: use `shipping-and-launch`.

## Quality bar
- Work in small, independently verifiable increments.
- Write a failing test before changing behavior.
- Run relevant tests, lint, type checks, and builds before completion.
- Never delete or weaken tests merely to make checks pass.
- Never commit secrets.
- Validate untrusted input at system boundaries.
- Ask before destructive operations, schema changes, or adding production
  dependencies.
```

最终推荐结构：

```text
my-project/
├── .agents/
│   ├── references/
│   └── skills/
├── .github/
│   ├── agents/
│   │   ├── code-reviewer.agent.md
│   │   ├── security-auditor.agent.md
│   │   ├── test-engineer.agent.md
│   │   └── web-performance-auditor.agent.md
│   └── copilot-instructions.md
├── skills-lock.json
└── ...项目文件
```

这些项目级配置适合提交到 Git，让团队成员获得同一套工作流。

---

## 7. 让 VS Code 重新发现配置

1. 在命令面板运行 **Developer: Reload Window**，或重新打开窗口；
2. 新建 Copilot Chat 会话；
3. 输入 `/skills`，打开 **Configure Skills**；
4. 确认所需 Skill 已启用；
5. 输入 `/agents`，确认四个 Persona 可见；
6. 右键 Chat 视图并选择 **Diagnostics**，检查配置错误。

Skill 的完整斜杠命令来自 `SKILL.md` frontmatter 中的 `name`：

```text
/spec-driven-development
/planning-and-task-breakdown
/test-driven-development
/code-review-and-quality
```

本仓库的 `/spec`、`/plan`、`/build`、`/test`、`/review` 和 `/ship` 短命令主要是
Claude Code 包装器。VS Code Copilot 默认使用完整 Skill 名称。只有另行创建
`.github/prompts/*.prompt.md`，才会出现对应的短别名。

---

## 8. 第一次完整使用：从想法到交付

### 8.1 澄清需求

需求模糊时：

```text
/interview-me
我想做一个团队任务管理 Web 应用。请一次只问一个问题，直到需求足够明确。
```

需求较清楚时：

```text
/spec-driven-development
为团队任务管理应用编写规格。先确认目标用户、范围、验收标准、技术约束和明确不做的内容；不要开始写产品代码。
```

审阅并确认生成的 `SPEC.md`。规格不正确时先修正规格，不要直接进入实现。

### 8.2 拆分计划

```text
/planning-and-task-breakdown
读取 SPEC.md，把工作拆成小而可独立验证的任务。为每个任务写验收标准和依赖顺序，保存到 tasks/plan.md 与 tasks/todo.md。先不要实现。
```

确认任务足够小、依赖顺序正确，并明确哪些工作可以并行。

### 8.3 逐个实现

```text
/incremental-implementation
读取 SPEC.md、tasks/plan.md 和 tasks/todo.md。只实现下一个未完成任务；配合 test-driven-development，先看到测试失败，再完成实现、运行验证并更新任务状态。
```

推荐循环：

```text
一个任务 → 失败测试 → 最小实现 → 测试通过 → 重构 → 相关验证 → 提交
```

不要让 Agent 一次完成整个大型项目。一个任务完成并验证后再进入下一个任务。

### 8.4 测试和调试

新增行为或修复缺陷：

```text
/test-driven-development
先写一个能证明需求或复现缺陷的失败测试，展示失败证据，再做最小修改使其通过并运行相关测试套件。
```

出现构建失败或未知错误：

```text
/debugging-and-error-recovery
先稳定复现问题，再定位、缩小范围、修复并添加回归保护。不要进行猜测式修改。
```

### 8.5 专业审查

在 Agent 选择器中选择 `code-reviewer`：

```text
审查当前分支相对 main 的改动。先读规格和测试，按 Critical、Required、Optional、Nit 分类，并给出验证结论。
```

涉及认证、用户输入、隐私或外部集成时，选择 `security-auditor`：

```text
对当前改动执行安全审计。先识别信任边界，只报告可利用或存在明确风险路径的问题，并给出修复建议。
```

测试覆盖不确定时选择 `test-engineer`；Web 页面性能问题选择
`web-performance-auditor`。没有真实测量数据时，性能 Persona 只能报告“潜在影响”，
不能伪造 LCP、INP 或 CLS。

### 8.6 准备发布

```text
/shipping-and-launch
基于已验证的构建，检查上线前条件、监控、分阶段发布和回滚方案。关键证据缺失时给出 NO-GO，不要假定通过。
```

---

## 9. Skill 选择速查表

| 当前任务 | 首选 Skill |
| --- | --- |
| 不清楚真正需求 | `interview-me` |
| 有模糊想法，需要比较方案 | `idea-refine` |
| 新项目、新功能、重大变更 | `spec-driven-development` |
| 已有规格，需要可执行任务 | `planning-and-task-breakdown` |
| 多文件实现 | `incremental-implementation` |
| 新增逻辑或修复缺陷 | `test-driven-development` |
| 构建、测试失败或行为异常 | `debugging-and-error-recovery` |
| UI 或可访问性 | `frontend-ui-engineering` |
| API 或公共接口 | `api-and-interface-design` |
| 安全相关 | `security-and-hardening` |
| 性能相关 | `performance-optimization` |
| 代码过于复杂 | `code-simplification` |
| 合并前审查 | `code-review-and-quality` |
| CI/CD | `ci-cd-and-automation` |
| 日志、指标、链路追踪 | `observability-and-instrumentation` |
| 迁移或废弃旧系统 | `deprecation-and-migration` |
| 发布上线 | `shipping-and-launch` |

也可以使用自然语言触发：

```text
使用 source-driven-development 技能，依据官方文档确认当前框架版本的推荐实现，再修改代码并附来源。
```

多个 Skill 同时适用时，按开发阶段组合，不要把所有 Skill 一次性塞入提示词。

---

## 10. 独立 Copilot CLI

### 10.1 安装 CLI

Linux/macOS 推荐使用官方脚本。非 root 用户默认安装到 `~/.local/bin`：

```bash
curl -fsSL https://gh.io/copilot-install | bash
```

如果终端找不到 `copilot`，将用户二进制目录加入 `PATH`：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

也可以在 Node.js 22 或更高版本下通过 npm 安装：

```bash
npm install -g @github/copilot
```

验证并登录：

```bash
copilot --version
copilot
```

首次交互会话中，如果尚未登录，按提示执行 `/login`。

### 10.2 安装 agent-skills 插件

推荐通过本仓库声明的 Marketplace 安装：

```bash
copilot plugin marketplace add addyosmani/agent-skills
copilot plugin install agent-skills@addy-agent-skills
```

直接仓库安装也能工作，但当前 CLI 已提示该方式将被弃用：

```bash
copilot plugin install addyosmani/agent-skills
```

### 10.3 验证和使用

```bash
copilot plugin list
copilot skill list
```

在交互会话中可执行：

```text
/plugin list
/skills list
```

启动项目会话：

```bash
cd ~/workspace/my-project
copilot
```

然后输入：

```text
使用 spec-driven-development skill，为这个项目编写规格，不要开始实现。
```

该插件注册 Skill，不提供 Claude Code 专用的 `/spec`、`/build` 等短命令。

---

## 11. 更新、卸载和共享

### 11.1 理解两个更新层次

使用本地克隆作为安装源时，更新分成两个独立步骤：

1. 把 GitHub 上游提交拉到本地 `agent-skills/` 源仓库；
2. 把更新后的 Skill、共享参考资料和 Persona 安装到目标工作空间，并刷新
  `.agent-skills-kit.lock`。

只执行 `git pull` 不会自动更新 `.agents/skills/`；只复制 Skill 又无法获得新的
上游提交。Persona 和顶层 `references/` 也不是普通 Skill 更新命令一定会处理的
内容。

### 11.2 使用标准 Skills CLI 更新

通过 `npx skills` 安装并保留 `skills-lock.json` 时：

```bash
npx skills update --project --yes
```

如果安装源是本地克隆，先更新源：

```bash
git -C ~/.local/share/agent-skills pull --ff-only
npx skills update --project --yes
```

Persona 和共享 `references/` 是手动复制的，源仓库更新后需重新复制并审阅差异。

运行前应确认 `node`、`npm` 和 `npx` 来自同一套 Node.js 安装；如果它们分别来自
用户目录和系统目录，优先修复运行环境，或者使用下一节不依赖 `npx` 的同步命令。

### 11.3 更新维护仓库固定的上游版本

进入维护仓库后，先只检查是否有新的正式版本：

```bash
./scripts/update-upstream.sh --check
```

默认选择最新的数字版本标签。确认后更新 Git submodule 的固定提交：

```bash
./scripts/update-upstream.sh
```

也可以明确指定版本或提交：

```bash
./scripts/update-upstream.sh 0.6.10
./scripts/update-upstream.sh <commit-sha>
```

更新脚本不会自动提交。它会拒绝脏的维护仓库或被修改的 submodule，切换版本、
暂存新的 Git-link、运行仓库验证，并打印建议的审阅和提交命令。继续执行：

```bash
git diff --cached --submodule=log -- vendor/agent-skills
./tests/run.sh
./scripts/verify.sh --staged
git commit -m "chore: update agent-skills to <version>"
```

这样其他电脑拉取维护仓库时都会得到同一个已审阅版本，而不是自动跟随随时变化的
上游 `main`。

### 11.4 将固定版本同步到目标项目

先预览，再安装并验证：

```bash
./scripts/install.sh --target /path/to/project --dry-run
./scripts/install.sh --target /path/to/project
./scripts/verify.sh --target /path/to/project
```

安装器的安全边界：

- 只管理上次写入 `.agent-skills-kit.lock` 的 Skill、参考资料和 Persona；
- 保留其他来源且名称不同的本地 Skill；
- 未拥有的同名内容默认使安装停止，只有 `--force-managed` 才会接管；
- 锁文件记录每个受管理条目的摘要；检测到本地修改时默认停止，审阅后只有
  `--force-managed` 才会恢复固定版本；
- 先在目标项目内的私有暂存目录准备完整配置，再整体替换；失败时恢复旧配置；
- 拒绝符号链接路径、损坏锁文件、脏 submodule 和不匹配的 Git-link；
- 默认保留目标项目已有的 Copilot Instructions；
- 不修改目标项目的产品代码和 Git 历史；
- 不依赖 `npm/npx`。

安装成功后，应在目标项目中审阅并提交这些项目配置：

```bash
cd /path/to/project
git status --short
git add .agents .github .agent-skills-kit.lock
git diff --staged
git commit -m "chore: update GitHub Copilot agent skills"
```

### 11.5 更新或卸载 CLI 插件

```bash
copilot plugin marketplace update addy-agent-skills
copilot plugin update agent-skills
```

更新所有插件：

```bash
copilot plugin update --all
```

卸载：

```bash
copilot plugin uninstall agent-skills
```

项目级 Skill 和独立 Copilot CLI 插件是两个安装层次。运行维护仓库的安装脚本不会
更新 CLI 插件；需要使用上面的 `copilot plugin update` 命令单独更新。

### 11.6 提交项目配置

```bash
git add .agents .github .agent-skills-kit.lock
git diff --staged
git commit -m "chore: configure agent skills for GitHub Copilot"
```

提交前检查是否包含未审阅脚本、外部地址、凭据或过宽权限。团队成员拉取仓库并
重新加载 VS Code 窗口后，即可发现这些项目级配置。

---

## 12. 常见问题

### 12.1 `/skills` 中没有新技能

依次检查：

1. VS Code 是否从正确的项目根目录打开；
2. Skill 是否位于 `.github/skills/`、`.agents/skills/` 或 `.claude/skills/`；
3. 每个 Skill 是否有独立目录和名称严格为 `SKILL.md` 的文件；
4. frontmatter 是否同时具有合法的 `name` 和 `description`；
5. `name` 是否与父目录名一致，并且只使用小写字母、数字和连字符；
6. `/skills` 配置页面中是否启用；
7. 是否已重新加载窗口并新建会话；
8. VS Code 和 Copilot Chat 是否需要升级。

### 12.2 Persona 不出现

- 确认文件位于 `.github/agents/`；
- 确认文件名以 `.agent.md` 结尾；
- 检查 YAML frontmatter；
- 在 `/agents` 中确认它没有被隐藏；
- 在 Chat Diagnostics 中检查解析错误。

### 12.3 安装或维护脚本无法执行

应从维护仓库根目录使用相对路径执行脚本。退出码 `126` 通常表示没有执行权限，
`127` 通常表示路径错误或脚本依赖的命令不存在。依次检查：

```bash
pwd
ls -l scripts/*.sh tests/*.sh
chmod 0755 scripts/*.sh tests/*.sh
bash -n scripts/*.sh tests/*.sh
./scripts/install.sh --help
```

如果 `vendor/agent-skills` 为空，初始化 submodule：

```bash
git submodule update --init --recursive
```

如果 Shell 语法检查失败，脚本可能被通用格式化器错误改写。Shell 中的
`VAR=value`、`[[ ... ]]` 和 `git -C` 不能被随意插入空格。使用 Git 恢复后再验证：

```bash
git diff -- scripts/
git restore scripts/
bash -n scripts/*.sh
```

`git restore` 会丢弃脚本中的未提交修改，必须先审阅 `git diff`。

### 12.4 `npx skills` 报 Node.js 或 npm 模块错误

典型表现是 `EBADENGINE`，或在 `await import(...)` 处出现语法错误。升级到
Node.js 22.20 或更高版本，关闭旧终端后重新检查 `node --version`。

如果错误是 `Cannot find module '@npmcli/config'`、`semver` 或其他 npm 内部模块，
通常是用户目录中的新 `node` 与系统目录中的旧 `npm/npx` 混用。检查三个命令的
来源：

```bash
command -v node npm npx
readlink -f "$(command -v node)"
readlink -f "$(command -v npm)"
readlink -f "$(command -v npx)"
```

三者应来自同一套 Node.js 安装。推荐使用 `nvm`、Volta 等版本管理器重新安装完整
Node.js 工具链，不要只替换 `node` 二进制。维护仓库的安装、更新和验证脚本不依赖
`npm/npx`，因此可以在修复 npm 期间继续使用。

临时检查可执行：

```bash
npx --yes -p node@22 -p skills -c 'node --version && skills add --help'
```

长期使用应修正默认 Node.js，而不是每次依赖临时运行时。

### 12.5 更新上游时报告本地修改

更新脚本要求维护仓库和第三方 submodule 都没有未提交修改。先停止更新并查看差异，
不要直接执行 `reset --hard`：

```bash
git status --short
git -C vendor/agent-skills status --short
git diff
git -C vendor/agent-skills diff
```

- 修改需要保留：提交到单独分支，或者使用 `stash push -u` 后同步；
- 修改只是确认无用的格式化结果：审阅后用 `git restore <file>` 恢复；
- submodule 内有实验代码：移到独立 fork 或分支，不要混入上游固定版本。

维护脚本主动停止是预期的安全行为，避免把未审阅修改带入所有目标项目。

### 12.6 npm 全局安装出现 `EACCES`

不要直接使用 `sudo npm`。优先选择：

1. 使用 Copilot CLI 官方安装脚本；
2. 使用 Node.js 版本管理器；
3. 将 npm 全局前缀改为用户可写目录。

### 12.7 Skill 能加载，但共享清单找不到

按第 4.4 节将源仓库的 `references/` 复制到 `.agents/references/`，或者保留完整
源仓库并在项目指令中明确参考资料位置。

### 12.8 项目 Skill 与插件 Skill 重名

这是允许的。Copilot 采用“先发现者优先”：项目级 Skill 优先于个人 Skill，个人
Skill 优先于插件 Skill。在项目内使用项目版本，离开项目后使用插件版本。

### 12.9 Monorepo 子项目看不到根目录配置

优先从仓库根目录打开 VS Code。确实需要继承父仓库配置时，启用：

```text
chat.useCustomizationsInParentRepositories
```

---

## 13. 最终验收清单

### VS Code

- [ ] 项目从正确的 Git 根目录打开；
- [ ] `.agents/skills/` 中每个 Skill 都有 `SKILL.md`；
- [ ] `.agents/references/` 中存在共享检查清单；
- [ ] `/skills` 能看到并启用所需 Skill；
- [ ] `.github/agents/` 中的 Persona 使用 `.agent.md` 后缀；
- [ ] `/agents` 能看到四个 Persona；
- [ ] `.github/copilot-instructions.md` 简短且只包含项目级规则；
- [ ] Chat Diagnostics 没有 frontmatter 或路径错误；
- [ ] 新会话中成功调用过至少一个 Skill；
- [ ] `./scripts/update-upstream.sh --check` 能正常报告上游版本；
- [ ] `./scripts/verify.sh --target /path/to/project` 验证安装成功。

### Copilot CLI

- [ ] `copilot --version` 成功；
- [ ] `copilot plugin list` 能看到 `agent-skills`；
- [ ] `copilot skill list` 能看到插件技能；
- [ ] 交互会话中的 `/skills list` 正常；
- [ ] 已完成登录，并能在测试项目中调用一个 Skill。

---

## 14. 官方资料

- [VS Code：Agent Skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills)
- [VS Code：Custom Agents](https://code.visualstudio.com/docs/copilot/customization/custom-agents)
- [GitHub：Adding agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-skills)
- [GitHub：Installing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli)
- [GitHub：Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
- [agent-skills Copilot 设置说明](../vendor/agent-skills/docs/copilot-setup.md)
- [agent-skills Copilot CLI 设置说明](../vendor/agent-skills/docs/copilot-cli-setup.md)
- [agent-skills 采用指南](../vendor/agent-skills/docs/adoption-guide.md)
