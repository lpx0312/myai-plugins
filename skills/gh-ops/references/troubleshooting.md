# 报错排查表 + Windows 专项

## A. 认证 / 权限

| 报错原文 | 原因 | 处理 |
|---|---|---|
| `HTTP 401: Bad credentials` | token 过期/被撤销 | `gh auth status`；从 keyhive 取新 token 覆盖 `GITHUB_TOKEN` |
| `HTTP 403: Resource not accessible by personal access token` | scope 不足，或 fine-grained token 未授权该仓库 | 看 `gh auth status` 的 scopes；补 `repo`/`workflow`/`admin:org` |
| `refusing to allow a Personal Access Token to create or update workflow` | 改 `.github/workflows/*` 需要 `workflow` scope | 换带 workflow scope 的 token |
| `GraphQL: Must have admin rights to Repository` | 需要 admin 权限（保护规则/转移/删除） | 换管理员账号或让用户操作 |
| `gh: To get started with GitHub CLI, please run: gh auth login` | 没有任何凭证 | 报出前置条件，**不要**代跑交互登录 |
| `gh auth switch` 没反应 | `GITHUB_TOKEN`/`GH_TOKEN` 环境变量优先于 keyring | `unset GITHUB_TOKEN GH_TOKEN` 后重试 |
| `Resource not accessible by integration` | 用的是 GitHub App / Actions 内的 GITHUB_TOKEN | 该动作需 PAT，改用 `secrets.PAT` |

## B. 仓库 / 分支

| 报错 | 原因 | 处理 |
|---|---|---|
| `Repository not found` | 名字拼错 / 私有且无权限 / 大小写 | `gh repo view OWNER/NAME` 验证；确认 token 能读 |
| `Name already exists on this account` | 仓库名占用 | 换名或 `gh repo view` 确认后直接复用 |
| `error: remote origin already exists` | 已有 origin | 去掉 `--remote`，或 `git remote set-url origin …` |
| `fatal: The current branch has no upstream branch` | 没 `-u` | `git push -u origin HEAD` |
| `protected branch hook declined` / `GH006` | 分支保护禁止直推 | 开分支走 PR，不要 `--admin` 绕过 |
| `! [rejected] ... non-fast-forward` | 远端有新提交 | `git pull --rebase` 后再推；禁 force |

## C. PR

| 报错 | 原因 | 处理 |
|---|---|---|
| `Head sha can't be blank` | 分支没推到远端 | `git push -u origin HEAD` |
| `No commits between main and feat/x` | 分支与 base 无差异 / base 搞错 | 确认 `-B` 与 `git log origin/main..HEAD` |
| `A pull request already exists for …` | 重复创建 | `gh pr view --json url` 取已有 PR |
| `GraphQL: Could not resolve to a Repository` | `--head` 的用户/仓库不存在 | fork 名与实际不符，检查 `gh repo view mylogin/repo` |
| `pull request is not mergeable` | 冲突 / 检查未过 / 需 review | `gh pr view N --json mergeable,mergeStateStatus` |
| `Review Can not approve your own pull request` | **自己的 PR 不能自审通过**（GitHub 硬限制） | 自测时改用 `gh pr review N --comment`；approve 只能由别的账号点 |
| `Pull request is not in the correct state` | 已合并/已关闭还想操作 | `gh pr view N --json state` |
| `--body` 里出现字面 `\\n` | 用了转义而不是文件 | 改用 `--body-file` |
| 正文中文乱码 | 源文件不是 UTF-8 | `file -i /tmp/pr.md`，用 Git Bash / UTF-8 写 |

## D. tag / release

| 报错 | 原因 | 处理 |
|---|---|---|
| `tag already exists` | tag 已存在 | 换版本号；确认可删才 `git push origin :refs/tags/X` |
| `Release not found` | tag 没有对应 release | `gh release create <tag>` 补建 |
| `Validation Failed: target_commitish is invalid` | `--target` 分支/SHA 不存在 | `git ls-remote --heads origin` 确认 |
| 附件 404 | 上传中断 / 名字冲突 | `--clobber` 重传，`--json assets` 验证 state |

## E. Actions

| 报错 | 原因 | 处理 |
|---|---|---|
| `workflow not found` | 文件名不带 `.yml`/不存在/未启用 | `gh workflow list --all` |
| `no workflow_dispatch trigger` | 缺触发器 | 加 `on: workflow_dispatch` 才能手动跑 |
| 日志里 `Bad credentials` | secret 里 token 失效 | `gh secret set` 更新 |
| `Resource not accessible`（fork PR） | `GITHUB_TOKEN` 在 fork PR 上只读 | 属预期，用 `pull_request_target` 或维护者批准 |

## F. Windows / Git Bash 专项

| 症状 | 原因 | 处理 |
|---|---|---|
| `--body` 多行变成一行 + `\\n` | shell 转义 | 写文件 + `--body-file`（`scripts/pr-body-gen.sh`） |
| 参数里的 `/path` 被改写 | MSYS 路径转换 | 前缀 `MSYS_NO_PATHCONV=1` |
| diff 全是换行变动 | `core.autocrlf` | `git config core.autocrlf input` + `.gitattributes` |
| `gh` 命令不存在 | PATH | 本机在 `/c/Tools/gh/bin/gh`；确认 `command -v gh` |
| `--template` 打出 `3.8992700359e+10` 这种科学计数法 | Go 模板把数值型 ID 当 float 渲染 | 取 ID 一律 `--json databaseId --jq '.[].databaseId'`，不要用 `--template` |
| `failed to parse jq expression … unexpected token` | jq 插值 `\(…)` 必须落在 **jq 的双引号字符串**里；Git Bash 里再套一层双引号极易错 | jq 程序用单引号包：`--jq '"state=\(.state)"'` |
| CMD/PowerShell 里 `&&` 报错或 heredoc 失效 | shell 不同 | 统一用 Git Bash 执行 |
| 中文文件名乱码 | 代码页 | `git config core.quotepath false` |
| 输出被分页器卡住 | pager | `GH_PAGER=cat` 或 `--no-pager` |

## G. 万能三连
```bash
gh auth status                                   # 谁在操作
gh <cmd> <sub> --help                            # 我用的参数对不对
bash ../scripts/preflight.sh                     # 当前仓库/分支/PR 状态
```
仍解不开：`GH_DEBUG=api gh <cmd>` 看真实请求与响应。
