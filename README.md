# Copilot Agent Skills Kit

用于跨电脑、跨项目复用 GitHub Copilot Agent Skills 的轻量维护仓库。

本仓库不复制第三方源码，而是通过 Git submodule 固定
[`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills) 的已审阅版本。
安装脚本会把该固定版本的 Skill、共享参考资料和 Persona 部署到任意现有项目。

运行环境要求 Linux、Bash 4.2+、Git、`rsync` 及常见 GNU coreutils/findutils。

详细中文说明见 [从零开始指南](docs/GITHUB_COPILOT_AGENT_SKILLS_GUIDE_ZH.md)。

## 仓库内容

```text
.
├── docs/                         中文完整指南
├── scripts/
│   ├── install.sh                安装到目标项目
│   ├── update-upstream.sh        检查或更新上游固定版本
│   └── verify.sh                 验证维护仓库或目标安装
├── templates/
│   └── copilot-instructions.md   新项目默认指令模板
├── tests/run.sh                  Bash 集成测试
└── vendor/agent-skills/          固定版本的上游 Git submodule
```

## 新电脑快速开始

### 1. 克隆维护仓库

```bash
git clone --recurse-submodules <repository-url> copilot-agent-skills-kit
cd copilot-agent-skills-kit
./scripts/verify.sh
```

克隆时遗漏 submodule 参数可补做：

```bash
git submodule update --init --recursive
```

### 2. 安装到项目

目标项目目录必须已经存在：

```bash
./scripts/install.sh --target /path/to/project --dry-run
./scripts/install.sh --target /path/to/project
./scripts/verify.sh --target /path/to/project
```

安装后在 VS Code 中执行 **Developer: Reload Window** 并新建 Copilot Chat 会话。
通过 `/skills` 和 `/agents` 检查发现状态。

## 安装器行为

安装器管理以下内容：

- `.agents/skills/<name>/`
- `.agents/references/`
- `.github/agents/<name>.agent.md`
- `.agent-skills-kit.lock`

重要边界：

- 目标项目已有的 `.github/copilot-instructions.md` 默认不会被覆盖；
- 与本工具包无关且名称不同的本地 Skill 会被保留；
- 未被锁文件拥有的同名 Skill、参考资料或 Persona 默认导致安装停止；
- 锁文件记录每个受管理条目的内容摘要；本地修改默认停止安装，不会静默覆盖；
- 使用私有暂存目录完成复制和验证后再替换目标配置，失败时恢复旧状态；
- 上一次由本工具包管理、未被本地修改且新上游版本已删除的文件会被清理；
- 符号链接路径、损坏锁文件、脏 submodule 或与 Git-link 不一致的源码会被拒绝；
- 不执行目标项目代码，不修改目标项目 Git 历史；
- 不依赖 npm 或 npx。

明确需要替换 Copilot Instructions 时：

```bash
./scripts/install.sh \
  --target /path/to/project \
  --force-instructions
```

审阅同名本地内容并确认要由工具包接管时，显式执行：

```bash
./scripts/install.sh \
  --target /path/to/project \
  --force-managed
```

该参数会覆盖所有检测到的未拥有同名内容，不能在未审阅 dry-run 输出时使用。
它也用于明确放弃已管理文件中的本地修改。长期项目规则应写入项目自己的
`.github/copilot-instructions.md`，不要直接修改镜像安装的 Skill 或 Persona。

## 维护上游版本

### 只检查新版本

```bash
./scripts/update-upstream.sh --check
```

### 更新到最新数字版本标签

```bash
./scripts/update-upstream.sh
```

### 更新到指定版本或提交

```bash
./scripts/update-upstream.sh 0.6.10
./scripts/update-upstream.sh <commit-sha>
```

更新会暂存新的 submodule Git-link，但不会自动提交。审阅并验证变化：

```bash
git diff --cached --submodule=log -- vendor/agent-skills
./tests/run.sh
./scripts/verify.sh --staged
git commit -m "chore: update agent-skills to <version>"
```

然后在每个目标项目重新运行安装和验证命令，并提交目标项目中的配置变化。

## 回滚

查看历史中固定过的上游提交：

```bash
git log --oneline --submodule -- vendor/agent-skills
```

将维护仓库回退到之前的正常提交，重新初始化 submodule，再安装到目标项目：

```bash
git checkout <known-good-kit-commit>
git submodule update --init --recursive
./scripts/install.sh --target /path/to/project
./scripts/verify.sh --target /path/to/project
```

不要在目标项目中使用破坏性的 `git reset --hard`；让安装器根据固定版本恢复其管理的
文件即可。

## 验证

```bash
bash -n scripts/*.sh tests/*.sh
./tests/run.sh
./scripts/verify.sh
```

验证脚本会检查：

- submodule 已初始化且与 Git-link 一致；
- submodule 没有本地修改；
- 每个 Skill 的目录名与 frontmatter `name` 一致；
- 四个必要 Persona 存在；
- Shell 脚本语法正确；
- 指定目标时，所有受管理文件及锁定提交一致。

普通 `./scripts/verify.sh` 只信任已经提交到维护仓库的 Git-link。更新脚本暂存新
Git-link 后，应使用 `./scripts/verify.sh --staged` 验证候选版本；提交完成后再恢复
使用普通验证命令。

## 发布到自己的 Git 托管服务

本地仓库不会自动配置远程地址。创建空的 GitHub/GitLab 仓库后执行：

```bash
git remote add origin <repository-url>
git push -u origin main
```

推送前确认远程仓库中不包含凭据、企业内部地址或不应公开的信息。第三方代码仍由
submodule URL 指向原作者仓库，许可证保留在 submodule 中。

## 常用命令

| 操作 | 命令 |
| --- | --- |
| 检查上游版本 | `./scripts/update-upstream.sh --check` |
| 更新上游固定版本 | `./scripts/update-upstream.sh [REF]` |
| 预览目标安装 | `./scripts/install.sh --target PATH --dry-run` |
| 安装到目标 | `./scripts/install.sh --target PATH` |
| 验证维护仓库 | `./scripts/verify.sh` |
| 验证目标项目 | `./scripts/verify.sh --target PATH` |
| 运行集成测试 | `./tests/run.sh` |

## 第三方声明

`vendor/agent-skills` 是独立 Git submodule，来源为
[`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)，按其 MIT
许可证使用。本维护仓库不修改或重新声明第三方项目的所有权。
