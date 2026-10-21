---
name: dir-diff
description: 对比两个目录的差异（哪些文件内容不同、只在哪边存在），覆盖 Linux 本地、Windows 本地、本地与远程跨机、远程与远程四类场景。当用户提到"对比两个目录"、"目录差异"、"比较两个文件夹"、"两边文件不一样"、"哪个文件改了"、"目录一致性检查"、"备份和源不一样"、"发布前后对比"、"增量检查"等时使用，即使只是随口问怎么 diff 目录。
---

# 目录差异对比（跨 Linux / Windows / 远程机）

核心事实：**对比本身永远不慢**（5000 文件毫秒级），瓶颈只出现在跨机器网络传输——所以策略是"本地直接比，跨机只传清单（manifest）不传文件"。

## 场景路由（先判断属于哪类）

| 场景 | 方法 |
|---|---|
| Linux 本地 / 远程机内部 | `diff -rq A B`（看内容差异）；`diff -r A B`（看具体行） |
| 想知道"怎么同步才能一致" | `rsync -avn --checksum A/ B/`（dry-run 预演，见坑 1） |
| Windows 本地（有 Git Bash） | 同上，**Git Bash 自带 GNU diff，行为与 Linux 完全一致** |
| Windows 无 Git Bash | `robocopy /L /MIR`（坑多，见坑 4/5，仅兜底） |
| 本地 ↔ 远程 / 远程 ↔ 远程 | 本 skill 的 manifest 法（下节） |
| 只看结构不读内容 | `diff <(cd A && find . \| sort) <(cd B && find . \| sort)` |

## 跨机对比：manifest 法（核心流程）

Git Bash 没有 rsync，`rsync -avn user@host:...` 在 Windows 本地走不通。标准流程（已实测 Windows↔Linux 全通，含中文/空格文件名）：

```bash
# 1. 远程生成清单（ssh-mcp execute-command；不必上传脚本，内联即可，
#    输出与 dir-manifest.sh gen 完全一致）
ssh 远端 'cd /目标目录 && find . -type f -exec md5sum -- {} + 2>/dev/null \
  | sed -E "s/^([0-9a-f]{32}) [ *]/\1 /" | sort -k2' > remote.manifest

# 2. 本地生成清单
bash "<skill目录>/scripts/dir-manifest.sh" gen /本地目录 > local.manifest

# 3. 对比（也可直接拿两个清单 diff，但 cmp 报告更好读）
bash "<skill目录>/scripts/dir-manifest.sh" cmp remote.manifest local.manifest
```

cmp 输出 `DIFF 路径 [hashA -> hashB]`、`ONLY-IN-A/B 路径` 和 SUMMARY 统计；退出码 0=一致 1=有差异 2=错误。清单传输用 sftp/scp/ssh-mcp download 均可（注意 ssh-mcp 的 download/upload 只允许工作区路径，先落到工作区）。

脚本也可整体上传到远程用（Linux bash 直接跑，无额外依赖：find/md5sum/sed/awk/sort）。

## 快速 vs 全量：怎么选

| 需求 | 手段 | 依据 |
|---|---|---|
| 又快又准（默认） | `diff -rq` | 读内容算哈希，本地磁盘上也是亚秒级，没理由用更糙的 |
| 同步预演 | `rsync -avn`（quick check） | 只比 size+mtime，**会漏报**（坑 1），报告"将复制/删除什么" |
| 同步预演且要准 | `rsync -avn --checksum` | 校验内容 |
| 跨机 | manifest 法（md5） | 跨机没有"快"选项：要么传文件比（慢），要么两端各算哈希只传清单 |

## 坑位清单（这些约定为什么存在）

1. **`rsync -avn` 默认 quick check（size+mtime）会漏报**：等长且 mtime 接近但内容不同的文件不会被列出（实测踩中）。要内容级结论必须 `--checksum`。
2. **rsync 尾部斜杠语义**：`rsync a/ b/` 是"a 的内容进 b"；`rsync a b/` 会变成 `b/a/`。dry-run 对比永远写 `A/ B/`。
3. **diff 的退出码 1 是"有差异"不是错误**：0 一致、1 有差异、2 才是真出错。脚本里别把 1 当失败。
4. **Git Bash 调 robocopy 会被 MSYS 路径转换吃掉开关**：`/L` 被转成 `L:/` 报"无效参数"。必须 `MSYS_NO_PATHCONV=1 robocopy ...` 前缀。
5. **robocopy 按 mtime 判断会误报**：内容相同但时间戳不同的文件也列入复制清单，输出还难解读。有 Git Bash 就不要用 robocopy 做对比。
6. **Git Bash 的 md5sum 输出带 `*`（binary 标记）**：`hash *./file` 与 Linux 的 `hash  ./file` 格式不同，直接 diff 两份清单会整行错位。统一用 `sed -E 's/^([0-9a-f]{32}) [ *]/\1 /'` 归一（脚本和内联命令都已带）。
7. **md5sum 清单行里路径含空格时不能按列拆**：manifest 解析用 `substr($0, 34)`（32 位哈希 + 1 空格之后）而不是 `$2`。
8. **`git diff --no-index` 不显示空目录差异**（git 不跟踪空目录）；对比符号链接要 `diff -rq --no-dereference`，否则比的是链接目标文件。
9. **符号链接和空目录不进 manifest 清单**（`find -type f`）；要对比它们就用坑 8 的 diff 方式。
10. **awk 读两份清单判别第一份用 `FNR == NR`**，不要用 `FILENAME == ARGV[1]`（同一路径自比时后者会把两份都算进第一份，全报 ONLY-IN-A）。
11. **中文文件名**：两端 locale 都是 UTF-8 时清单可直接比；远程非 UTF-8 locale（老系统 GBK）会错位，先 `export LANG=en_US.UTF-8` 再生成。

## 何时不用本 skill

- 单个文件对比：`diff a.txt b.txt` 一句搞定。
- 明确要同步（不是看差异）：直接 `rsync -av --checksum` 干活，不用先看。
- 两台 Linux 之间且已免密：`rsync -avn --checksum` 比 manifest 法更省事（一次命令直接出结论）。
