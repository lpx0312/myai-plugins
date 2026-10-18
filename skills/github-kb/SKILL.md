---
name: github-kb
description: 本地 GitHub 知识库 + GitHub 全网检索（只读）。维护 D:\AI\github-code 下已克隆仓库的 GITHUB_KB.md 目录；用 gh search 搜仓库/issue/PR/代码，并读取 issue / PR 正文与评论来回答"GitHub 上有没有 X、谁遇到过我这个问题、最后怎么解决的"。当用户说"clone 到知识库""找 GitHub 上的项目""帮我查下这个报错在 GitHub 上有没有人提过""搜 issue / PR""看看这些 issue 在说什么"时使用。不做任何写操作——建 issue、评论、提 PR、评审、合并、打 tag、发 release、跑 Actions 一律交给 skill gh-ops。
license: MIT
---

# GitHub 知识库（本地 KB + 全网检索）

**定位：只读。** 两件事：

1. **本地 KB**：把仓库克隆到知识库目录，维护 `GITHUB_KB.md` 目录，之后可离线翻代码。
2. **全网检索**：用 `gh search` 在 GitHub 上找仓库、issue、PR、代码，回答"有没有 X / 谁遇到过这个问题"。

**不做**（交给 `gh-ops`）：建仓、提 PR、评审、合并、打 tag、发 release、触发 Actions、secret/ruleset、`gh api` 写操作。
用户一句话里同时要"查"又要"改"时：本技能负责查，改的部分转给 `gh-ops`。

## 配置

| 变量 | 本机值 | 说明 |
|---|---|---|
| `GITHUB_KB_PATH` | `D:\AI\github-code` | KB 根目录（当前 30 个仓库，约 20 条目录） |
| `GITHUB_TOKEN` | 已由环境提供 | 私有仓库与提高限流；不要硬编码 |

本机 KB 已有 `GITHUB_KB.md`，条目格式：

```markdown
## 分类名

### [repo-name](/repo-name)
一句话说明这个项目做什么、关键技术点。
```

## 一、本地 KB 工作流

### 查：先本地后远端
```bash
ls "$GITHUB_KB_PATH"                       # 看有什么
grep -n -i "关键词" "$GITHUB_KB_PATH/GITHUB_KB.md"   # 先在目录里找
rg -l "关键词" "$GITHUB_KB_PATH" --max-depth 2       # 再在代码里找
```
命中本地就别去联网了。

### 克隆进 KB（用户说"clone X"默认放这里）
1. 名字不确定 → 先 `gh search repos <关键词>` 确认 `owner/name`
2. `git clone https://github.com/<owner>/<name>.git "$GITHUB_KB_PATH/<name>"`
   （或 `gh repo clone <owner>/<name> "$GITHUB_KB_PATH/<name>"`）
3. 读 README / 关键文件，写一句话说明
4. 往 `GITHUB_KB.md` **对应分类**下追加条目（格式照上表，不重排已有内容）
5. 回报：克隆到哪 + 目录已更新

**注意**：已存在的目录不要静默覆盖；确实要更新就 `git -C <dir> pull --ff-only`。

## 二、全网检索（gh search）

| 目标 | 命令 |
|---|---|
| 找项目 | `gh search repos "<关键词>" --limit 10 --sort stars` |
| 找项目（按语言/星数/tag） | `gh search repos "language:go stars:>1000 topic:k8s" --limit 20` |
| 找 issue | `gh search issues "<报错/关键词>" --limit 20` |
| 在某仓库里找 issue | `gh search issues --repo owner/repo <关键词> state:open` |
| 找 PR | `gh search prs --repo owner/repo <关键词> is:merged` |
| 找代码片段 | `gh search code "<函数名>" --language go --limit 20` |
| 找 commit | `gh search commits "<信息>" --repo owner/repo` |
| 结构化输出 | 加 `--json fullName,stargazersCount,description` / `--jq` |

### ⚠️ 搜索语法坑（gh 官方 skill 明确警告，实测复现）

**限定词必须各写一个 token，不能整串加引号**：

```bash
gh search issues repo:cli/cli is:open author:monalisa     # ✅ 正确
gh search issues "repo:cli/cli is:open"                   # ❌ 被当成一个 keyword → Invalid search query
gh search repos "language:python stars:>1000"             # ❌ 同上，实测返回 0 条
gh search repos language:python stars:>1000               # ✅
```

规则：**只有多词自由文本才加引号**（`gh search issues "broken feature"`）；
`repo:` / `is:` / `author:` / `label:` / `language:` / `stars:` / `topic:` 一律裸写。
很多限定词也有对应 flag（`--repo`、`--author`、`--label`），可用 flag 就用。

### Bot 作者
`--author dependabot` 匹配不到（Bot 是 GitHub App 身份）→
用 `--app dependabot`（会自动展开成 `author:app/dependabot`）或 `--author "dependabot[bot]"`。

### 自然语言提问用语义搜索
用户是"描述现象"而不是给关键词时（"我这个报错在 GitHub 上有人提过吗"），加语义检索：

```bash
gh search issues "<一句自然语言描述>" --search-type semantic --limit 20
gh search issues "<描述>" --search-type hybrid --limit 20     # 关键词+语义混合
```
`--search-type` 只对 issues 有效（github.com / GHEC），默认 `lexical`（精确匹配）。

### 常用限定词速查
`repo:owner/name` `is:open|closed` `is:merged|unmerged` `author:@me` `in:title|body|comments`
`label:bug` `language:go` `stars:>1000` `topic:mcp` `comments:>5` `created:>2025-01-01`

## 三、读正文：issue / PR / 评论（只读）

**为什么必须有**：很多答案不在代码里，而在 issue 正文或某条评论里
（"这个坑有人提过吗""最后是装老版本绕过去的"）。搜索只吐元数据是不够的，
要能钻进去读。

### 单条详情
```bash
gh issue view 123 --repo owner/repo                # 正文
gh issue view 123 --repo owner/repo --comments     # 正文 + 全部评论（最常用）
gh pr view 456 --repo owner/repo --comments

# 结构化取（要批量处理时用）
gh issue view 123 --repo owner/repo --json number,title,body,state,comments,labels,createdAt,closedAt
gh pr view 456 --repo owner/repo --json number,title,body,state,merged,mergedAt,comments,reviews
```

### 直接搜评论内容（答案藏在评论里的最佳入口）
```bash
gh search issues --repo owner/repo --match comments "<报错原文或关键词>" --limit 20
gh search issues --match title,body,comments "<关键词>" --limit 30      # 跨域全 GitHub 搜
gh api "search/issues?q=repo:owner/repo+<关键词>+in:comments" --jq '.items[].html_url'
```
`--match` 取值范围：`title` / `body` / `comments`（可组合）。

### 标准姿势：先搜 → 挑 → 读 → 总结
```bash
# 1) 搜，拿到候选编号
gh search issues "<一句话/报错>" --search-type semantic --limit 10 \
  --json number,title,repository,commentsCount --jq '.[] | "\(.repository.nameWithOwner)	\(.number)	评论\(.commentsCount)	\(.title)"'

# 2) 按相关度挑前 3~5 条读正文+评论（控制 token，不要无脑全读）
for id in 123 456 789; do
  echo "===== #$id ====="
  gh issue view "$id" --repo owner/repo --comments
done

# 3) 按下面格式总结
```
- 命中超过 10 条时**只读前 3~5 条**，其余给出编号列表让用户自己挑，别一次读完。
- 评论特别长（几十条）时：先读正文 + 最后几条 + 带 `fixed`/`workaround`/`solution` 字样的。
- 想看结论优先的：`gh pr view N --json reviews` 找 approve 后的总结。

## 四、输出规范（关键）

**不要倒原始结果列表。** 用户要的是"都给我查出来 + 我下一步看哪个"，所以每次检索都收敛成：

```markdown
问题：<用户原问题>
命中：<N> 条（已按相关度筛到前 <M> 条）

1. **owner/repo#123 — <标题>**
   为什么相关：一句话
   链接：url

suspected_scope=<问题落在哪块代码/哪个组件>
strongest_evidence=<最强的一条证据>
next_best_action=<open code / open issue / clone 进 KB>
next_target=<owner/repo#123 或 path/to/file.go>
confidence=high|medium|low
```

配套动作：
- 命中仓库值得留着 → 问用户要不要 clone 进 KB（不要擅自 clone）
- 结果太少 → 换限定词/去掉 `repo:` 再搜一轮，并说明换了什么
- 结果太多 → 加 `language:` / `stars:>N` / `is:merged` 收窄

## 五、边界

- **只读**：本技能不产生 GitHub 上的任何变更。读再多 issue / PR / 评论都属于"查"，放开读。
- **读 ≠ 操作**：本期"读正文并总结"归本技能；但只要涉及**写**（发评论、加标签、关 issue、
  开 PR、合并、评审结论），一律停手转给 `gh-ops`。
  典型分界：用户说"总结一下这些 issue"→ 本技能；"去那个 issue 底下回一句"→ gh-ops。
- 用户要"提 PR / 合并 / 建仓库 / 打 tag / 发版 / 跑 Actions" → 交给 `gh-ops`。
- 认证状态、token 优先级、Windows 坑 → 看 `gh-ops` 的 `references/troubleshooting.md`
  （`gh auth status` 与 `scripts/preflight.sh` 两边通用）。
- 本地 `git` 操作（commit/rebase/stash）用 git 本身，不属于本技能。
