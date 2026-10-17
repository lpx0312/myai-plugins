---
name: sudo-compat
description: 为 shell/bash 脚本添加 sudo 兼容（root 与非 root 自适应）改造，让脚本既能被 root 直接执行，也能被普通用户通过 sudo 自动提权执行。当用户提到「脚本适配 sudo」「让脚本能 sudo 运行」「不用每次都 sudo bash」「cron 里跑脚本没权限」「脚本权限不足/Permission denied」「root 检查太死板」或需要对 shell 脚本做权限/提权兼容改造时，务必使用本 skill。适用于任何需要写系统文件（/etc/hosts、/etc/crictl.yaml）、安装到 /usr/local、改 crontab、操作 /etc 下目录的安装/配置脚本。
---

# sudo 兼容改造（sudo-compat）

## 这个 skill 解决什么问题

很多安装/配置脚本一开始就写死「必须是 root，否则 `exit 1`」：

```bash
if [ "$(id -u)" -ne 0 ]; then
    echo "需要 root 权限"
    exit 1
fi
```

这会导致两个麻烦：
- 用户每次都得 `sudo bash xxx.sh`，没法直接 `./xxx.sh` 或 `curl ... | bash`。
- cron 环境、CI 环境、自动化流水线里经常没有交互式 tty，要么得提前配 `NOPASSWD`，要么直接失败。

更好的做法是**让脚本自己探测权限**：root 直接执行；非 root 且有 `sudo` 就自动 `sudo -n`（非交互，不卡密码）；非 root 且无 `sudo` 才报错。这样同一个脚本在任何场景都能跑，对调用方完全透明。

## 核心改造模式（必读）

把下面这段「sudo 兼容基础设施」加到目标脚本里（放在配置变量之后、需要 root 的操作之前）。这是整个 skill 的基石，所有改造都围绕它展开：

```bash
# ==================== sudo 兼容 ====================
SUDO_CMD=()
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        # -n: 非交互模式，避免脚本卡住等待输入密码（cron/CI 无 tty 尤其重要）
        SUDO_CMD=(sudo -n)
    else
        log "❌ 当前用户非 root，且未找到 sudo，无法完成需要 root 的操作"
        exit 1
    fi
fi

# 以 root 身份执行命令（root 时直接跑，非 root 时走 sudo -n）
run_root() {
    if [ "${#SUDO_CMD[@]}" -gt 0 ]; then
        "${SUDO_CMD[@]}" "$@"
    else
        "$@"
    fi
}

# 先用当前用户试，失败了再用 root 兜底（适合「能省则省」的只读/可写不确定场景）
run_with_fallback() {
    "$@" 2>/dev/null || run_root "$@"
}
```

**为什么用 `sudo -n` 而不是 `sudo`**：`-n`（non-interactive）让 sudo 在需要密码时直接失败而不是挂起等待输入。在 cron、CI、`curl | bash` 这种没有 tty 的管道里，`sudo` 会无限等待 stdin，把脚本/调度卡死。代价是：手动交互执行且没配 `NOPASSWD` 时会失败——这是有意的，因为脚本无法安全地替用户输密码；这种情况应让用户显式 `sudo bash xxx.sh`（此时脚本身份已是 root，根本不走 `SUDO_CMD` 分支）。

**为什么用 bash 数组 `SUDO_CMD=()` 而不是字符串**：数组能正确处理带空格/引号的参数，不会因二次分词出错。`"${SUDO_CMD[@]}" "$@"` 把 `sudo -n` 和被调用命令的参数干净地拼到一起。

### 三个函数怎么选

| 函数 | 用途 | 例子 |
|---|---|---|
| `run_root` | **一定**需要 root 的操作 | 写 `/etc/hosts`、`mkdir /etc/xxx`、改 root 的 `crontab`、`cp` 到 `/usr/local` |
| `run_with_fallback` | 不确定是否需要 root，能省则省 | 读 `/etc/xxx`（普通用户通常可读）、`tee` 写配置文件 |
| 不包装 | 纯用户态操作 | `curl` 下载、`grep`、变量赋值、`log` 打日志 |

判断原则：**先想清楚「普通用户能不能干」**。能 → 不包装或用 `run_with_fallback`；不能 → 用 `run_root`。别无脑给所有命令套 `run_root`，那样普通用户场景下会平白多出 sudo 调用，还可能因为不需要密码的 NOPASSWD 未配置而失败。

## 改造工作流

按这个顺序做，不要跳步：

1. **先备份**。改脚本前务必 `cp xxx.sh xxx.sh.bak.$(date +%Y%m%d_%H%M%S)`。权限相关的改动容易引入隐蔽 bug，留个能回滚的副本是基本素养。

2. **通读脚本，列出所有需要 root 的点**。重点找这几类操作：
   - 写 `/etc`、`/usr`、`/var`、`/root` 下的文件
   - `mkdir` 到上述目录
   - `cp`/`mv`/`cat >` 到上述目录
   - `crontab`（改的是谁的 crontab？root 还是当前用户？见下方注意点）
   - `systemctl`、`chmod`/`chown` 系统文件
   - 安装二进制到 `/usr/local/bin`、创建软链到 `/usr/bin`
   - 「权限不足」的前置 `exit 1` 检查（要把死检查改成自适应）

3. **注入「sudo 兼容基础设施」代码块**（上面那段），位置放在 `set -euo pipefail` / 配置变量 / `log()` 函数定义之后，第一个需要 root 的操作之前。

4. **把死检查换成自适应**。原来的 `if [ "$(id -u)" -ne 0 ]; then exit 1; fi` 整段删掉，由上面的 `SUDO_CMD` 探测块取代。

5. **逐个给需要 root 的命令加包装**，按「三个函数怎么选」表判断。

6. **特殊处理写文件场景**（见下方「最容易踩的坑」），不能简单 `echo > file`。

7. **`bash -n` 语法校验**，有 `shellcheck` 也跑一遍。

8. **diff 一下备份和改后的版本**，人工 review 每一处包装是否合理。

## 最容易踩的坑（必读）

### 坑 1：重定向不能直接加 sudo

```bash
# ❌ 错：重定向是当前 shell 做的，sudo 管不到；文件还是没权限写
sudo echo "xxx" > /etc/hosts
run_root echo "xxx" > /etc/hosts   # 同样错！> 由当前用户 shell 处理
```

正确做法二选一：

```bash
# ✅ 方法 A：用 tee（tee 进程被 sudo 启动，由它写文件）
echo "xxx" | run_root tee /etc/hosts >/dev/null

# ✅ 方法 B：把整条命令塞进 sudo bash -c（包括重定向）
run_root bash -c 'echo "xxx" > /etc/hosts'
```

### 坑 2：临时文件 + 原子覆盖

改 `/etc/hosts` 这类系统文件时，推荐「先写临时文件，再覆盖」，避免写一半中断留下损坏文件：

```bash
TMP_FILE="${HOSTS_FILE}.tmp.$$"   # $$ 当前 PID，避免并发撞名
umask 077                          # 临时文件含敏感内容，收紧权限

# 生成新内容 → 用 root 写临时文件
generate_content | run_root tee "${TMP_FILE}" >/dev/null
# 追加行
run_root bash -c "echo '${LINE}' >> '${TMP_FILE}'"
# 原子覆盖（临时文件和目标同分区才能 cp 覆盖）
run_root cp "${TMP_FILE}" "${HOSTS_FILE}"
run_root rm -f "${TMP_FILE}"        # 清理
```

临时文件要放**和目标同分区**（比如改 `/etc/hosts` 就把临时文件放 `/etc/hosts.tmp`），否则跨分区 `cp` 是「复制」不是「移动」，`mv` 跨分区也非原子。

### 坑 3：crontab 到底改谁的

`crontab -l` / `crontab -` 默认操作的是**当前用户**的 crontab。一个普通用户跑脚本：

- 不加包装：写到普通用户的 crontab → cron 以普通用户身份跑 → 如果 cron 里的命令要改系统文件，又得靠脚本自身的 sudo 适配 + 该用户的 `NOPASSWD`，否则 cron 里 `sudo -n` 会失败（cron 无 tty）。
- 加 `run_root`：写到 **root 的 crontab** → cron 以 root 身份跑 → 最省心，cron 里的命令不需要再 sudo。

**推荐写 root 的 crontab**（cron 环境最稳定）。所以 crontab 相关命令都要 `run_root crontab ...`。

### 坑 4：`set -euo pipefail` + 管道 + sudo 的交互

`run_root` 内部展开成 `sudo -n cmd` 时，如果 `cmd` 失败，`sudo` 的退出码会透传，`set -e` 正常生效。但要小心 `run_with_fallback`：

```bash
run_with_fallback() {
    "$@" 2>/dev/null || run_root "$@"
}
```

第一次 `"$@"` 失败会被 `||` 接住，不会触发 `set -e` 退出——这是有意的（就是要试两次）。但如果 `run_root "$@"` 也失败，`set -e` 会正常让脚本退出。所以 `run_with_fallback` 适合「第一次失败正常，第二次还失败才算真失败」的场景。

### 坑 5：cron 命令要不要套 sudo

如果入口脚本调用一个**内部已自带 sudo 适配**的子脚本，那么写到 cron 里的命令**不需要再套 sudo**——子脚本会自己处理。重复套 `sudo` 反而可能因 cron 无 tty 又需要密码而失败。

## 决策检查清单

改完后，对着这个清单过一遍：

- [ ] 原 `id -u -ne 0` 的死 `exit 1` 已替换为 `SUDO_CMD` 自适应探测块
- [ ] 每个「绝对需要 root」的命令都用 `run_root` 包装
- [ ] 写文件没有 `sudo ... > file` 这种错误重定向（改用 `tee` 或 `bash -c`）
- [ ] 改系统文件用了「临时文件 + 原子覆盖」模式
- [ ] crontab 操作明确：要么写 root 的（`run_root crontab`），要么有意识写当前用户的
- [ ] cron 命令不重复套 sudo（如果调用的子脚本已自适应）
- [ ] 备份文件已生成
- [ ] `bash -n` 通过

## 参考案例

`references/` 下有完整的真实改造案例，直接对照抄结构：

- **`references/real-example-cf-speedtest.md`** —— 两个真实脚本（CF 最优 IP 写 hosts + cron 定时入口）的完整改造，包含改造前后的逐行对比、每处包装的取舍理由、坑的实测表现。当目标脚本和这个案例场景类似（写 `/etc/hosts`、配 crontab、有子脚本调用关系）时，先读它再动手。
