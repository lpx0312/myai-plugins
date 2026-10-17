# tag 与 release

## 1. tag 语义（先定规则再动手）

- `vMAJOR.MINOR.PATCH`（`v1.2.3`）—— 最常见，与 release 名一致。
- 预发布：`v1.2.3-rc1` / `-beta.1`；语义化版本里预发布 < 正式版。
- **附注 tag 优先**（`git tag -a`），轻量 tag 没有作者/日期/说明，release 时拿不到 `--notes-from-tag`。
- 一个 tag 只指一次提交，**发布后不要移动 tag**（要重发就发新版本号）。

## 2. 打 tag 并推送

```bash
git switch main && git pull --ff-only
git log --oneline -10                                  # 确认落点
git tag -a v1.2.0 -m "v1.2.0: 一句话摘要"
git push origin v1.2.0                                 # 只推这一个 tag
# 不要 git push --tags（会把本地实验 tag 全推上去）
```

改错 / 删除：
```bash
git tag -d v1.2.0                          # 本地
git push origin :refs/tags/v1.2.0          # 远端（破坏性，需授权）
```

同时打多个 / 给旧提交补 tag：
```bash
git tag -a v1.2.0 <sha> -m "…"
git tag --contains <sha>
git describe --tags --abbrev=0            # 最近一个 tag
```

## 3. 创建 release

```bash
# 推荐：附注 tag + 自动生成 notes（基于合并的 PR）
gh release create v1.2.0 --target main --generate-notes -t "v1.2.0"

# 手写 notes（真实换行，用文件）
gh release create v1.2.0 --target main -t "v1.2.0" -F /tmp/notes.md

# 自动生成 + 指定起点（只统计上个版本之后）
gh release create v1.2.0 --generate-notes --notes-start-tag v1.1.0

# 带附件（二进制 / 校验和 / sbom）
gh release create v1.2.0 -F /tmp/notes.md ./dist/app-linux-amd64 ./dist/app.zip ./dist/SHA256SUMS

# 预发布 / 草稿
gh release create v1.2.0-rc1 --prerelease -F /tmp/notes.md
gh release create v1.2.0 --draft -F /tmp/notes.md          # 先存草稿，人审后发布

# 不设为 Latest（维护旧版本补发时）
gh release create v1.1.5 --latest=false -F /tmp/notes.md
```

- `--target` 默认取仓库默认分支；写 tag 名或 SHA 都行。
- `--verify-tag`：tag 不存在就报错（防止误建 tag 指向非预期提交）。
- release 名 ≠ tag 名：`-t` 只改显示标题。
- 若 tag 已存在但 release 没建，直接 `gh release create <已存在tag>` 即可复用。

## 4. 后续维护

```bash
gh release list --limit 10
gh release view v1.2.0 --json tagName,name,isDraft,isPrerelease,assets,url
gh release view v1.2.0                      # 人读
gh release upload v1.2.0 ./dist/new.zip --clobber     # 补附件/覆盖
gh release download v1.2.0 --pattern "*.zip" -D ./dl
gh release edit v1.2.0 --draft=false                  # 草稿转正式
gh release edit v1.2.0 --prerelease=false --latest
gh release delete v1.2.0 --cleanup-tag --yes          # 连带删 tag，破坏性
```

## 5. 检查清单
- [ ] 版本号与 tag 一致、符合语义化规则
- [ ] tag 落在正确提交（`git show v1.2.0 --stat`）
- [ ] notes 里没有未发布内容、没有内部链接/密钥
- [ ] 附件能下载（`gh release view vX --json assets` 看 size/state）
- [ ] 预发布没被设成 Latest
