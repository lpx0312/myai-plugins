---
name: encoding-convert
description: 检测目录下文件的编码/换行符/BOM，并批量安全转换为 UTF-8 + LF（unix 换行）+ 无 BOM。当用户提到"看看文件什么编码"、"乱码"、"转 UTF-8"、"GBK 转 UTF-8"、"换行符 CRLF/LF"、"dos2unix"、"统一编码"、"unix 换行"、"老项目编码清理"、"传 Linux 前处理文件"等时使用，即使只是随口问这个目录编码乱不乱。
---

# 文件编码与换行符批量检测/转换（UTF-8 + LF）

对目录做三件事：检测每个文本文件的**编码、换行符（CRLF/LF）、UTF-8 BOM**，并可批量转换为 **UTF-8 + LF + 无 BOM**。核心价值是安全流程（先检测 → 确认 → 备份 → 转换 → 回读校验），不是"会不会转"。

## 安全约定（必须遵守）

1. **脚本默认只检测（dry-run），`--apply` 才写文件**。使用流程固定为：先跑默认检测 → 把清单汇报给用户 → 用户确认后加 `--apply` 执行。不要跳过汇报直接 `--apply`。
2. 默认生成 `.bak` 备份（`--no-backup` 关闭）；重复转换不会覆盖已有 `.bak`。
3. 自动排除 `.git/.svn/.hg/node_modules/target/build/dist/__pycache__/.idea/.vscode` 等目录；二进制文件自动跳过（`file` 判定）。
4. **Windows 专属文件完全不动**：`.bat/.cmd/.ps1/.vbs/.sln/.csproj` 等（cmd.exe 对 LF-only 的 .bat 有解析坑、中文依赖 GBK 代码页，VS 工程文件要求 BOM+CRLF）。显示为 `[SKIP-WIN]`，用户坚持要转时单独手工处理并提醒后果。
5. 默认去除 UTF-8 BOM（shebang、javac、部分解析器都烦 BOM）；`--keep-bom` 保留。

## 命令

```bash
# 本机 Git Bash（脚本路径即本 skill 的 scripts/ 目录下）
bash "<skill目录>/scripts/encoding-convert.sh" <目录>                  # 只检测
bash "<skill目录>/scripts/encoding-convert.sh" --apply <目录>          # 执行转换
bash "<skill目录>/scripts/encoding-convert.sh" --ext java,xml <目录>   # 只处理指定扩展名
bash "<skill目录>/scripts/encoding-convert.sh" --apply --from BIG5 <目录>  # 追加源编码
bash "<skill目录>/scripts/encoding-convert.sh" --keep-eol <目录>       # 只转编码不动换行
```

**远程 Linux**：先用 ssh-mcp 的 `write-file` 把脚本上传到远程 `/tmp/encoding-convert.sh`，再 `execute-command` 执行 `bash /tmp/encoding-convert.sh ...`（依赖 file/iconv/sed 均为 GNU 系标配）。

## 输出解读

每行：`文件路径 [标记] 详情`。标记含义：

| 标记 | 含义 |
|---|---|
| `[TODO]` | 检测模式下列出"将要做什么"（utf8<-GBK 去BOM CRLF->LF） |
| `[OK]` | 已转换，括号内是实际动作和来源编码 |
| `[SKIP]` | 已达标（utf-8/us-ascii + LF 无 BOM），无需处理 |
| `[SKIP-BIN]` | 二进制/非文本 |
| `[SKIP-WIN]` | Windows 专属文件，编码/换行均不动 |
| `[SKIP] empty` | 空文件 |
| `[FAIL]` | 所有候选编码都转不了，或转换结果不是合法 UTF-8 |

结尾 `SUMMARY` 行给出统计；**退出码 2 表示有 FAIL**，要如实向用户报告失败清单。`--ext` 过滤掉的文件静默跳过（skip-ext 只计数字）。

## 坑位清单（这些约定为什么存在）

1. **`file` 对 GBK 中文常误报 `iso-8859-1` 或 `unknown-8bit`** —— 脚本把它们当"编码未知的文本"，依次尝试 GBK → GB18030（+`--from` 追加），iconv 全失败才标 FAIL。
2. **GBK→UTF-8 无损安全，反向有损**（UTF-8 全量、GBK 部分覆盖）——所以只做单方向转换，绝不反向批量转。
3. **iconv 转换成功 ≠ 语义正确** —— 错误的源编码（如 Big5 被当 GBK）可能"成功"转出乱码。`--apply` 后务必 `head` 抽查 1-2 个含中文的转换结果再向用户报完成。
4. **UTF-16 文件**（Windows 记事本产物）靠文件头 BOM（FF FE / FE FF）识别，Git Bash 的 `file` 会把它误判成二进制，脚本已用 BOM 头兜底；但**无 BOM 的 UTF-16 仍会被当二进制跳过**（显示 `[SKIP-BIN]`），遇到可疑时手工 `file -bi` 确认。
5. 纯 ASCII 内容的 GBK 文件检测为 `us-ascii`，语义上已是 UTF-8 子集，只处理其换行/BOM，不动编码。
6. 写回用 `cat > 原文件` 而非 `mv`，保留原文件的权限和属主（root 场景重要）。

## 何时不用本 skill

- 单个文件看编码：直接 `file -bi <文件>`，不必起脚本。
- 只想把一个文件的 CRLF 转 LF：`sed -i 's/\r$//' <文件>` 一句搞定。
- 反向转 GBK / 转 CRLF：本 skill 不做（破坏性方向，单独讨论处理）。
