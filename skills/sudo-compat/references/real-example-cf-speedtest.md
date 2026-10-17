# 真实改造案例：CF 最优 IP 写 hosts + cron 定时

本文记录一次完整的 sudo 兼容改造，两个脚本配合使用：`local_set_bestip.sh`（写 `/etc/hosts`）和 `host_set_cfbest_cron.sh`（立即执行一次 + 写 root crontab 定时）。当你的目标脚本也是「改系统配置文件 + 配 cron 定时」时，直接对照本案例抄结构。

## 场景概述

- **local_set_bestip.sh**：从中心服务器拉最优 IP → 备份 `/etc/hosts` → 写入新行。需 root：创建 `/etc/hosts_cfbest_backup`、`cp /etc/hosts`、写回 `/etc/hosts`、清理旧备份。
- **host_set_cfbest_cron.sh**：入口脚本。① 立即下载并执行 local 脚本；② 写 root 的 crontab，每天定时再跑 local 脚本。

改造目标：两个脚本都能被普通用户直接执行（自动 sudo 提权），也能被 root 直接执行；cron 环境无 tty 也不会卡。

## 案例一：local_set_bestip.sh

### 改造前（核心部分）

```bash
log() { echo "[$(date '+%F %T')] $*"; }

# ---------- 0. 准备备份目录 ----------
mkdir -p "${BACKUP_DIR}" 2>/dev/null || { log "❌ 无法创建备份目录"; exit 1; }

# ---------- 2. 备份 hosts ----------
cp -a "${HOSTS_FILE}" "${BACKUP_FILE}"

# 清理旧备份
ls -1t "${BACKUP_DIR}"/hosts.*.bak 2>/dev/null | tail -n +$((BACKUP_RETAIN + 1)) | while IFS= read -r old; do
    rm -f "${old}"
done

# ---------- 3. 更新 hosts ----------
TMP_FILE="${HOSTS_FILE}.tmp.$$"
grep -v "${MARKER}" "${HOSTS_FILE}" | grep -v " ${TARGET_DOMAIN}\b" | grep -v " ${TARGET_DOMAIN} " > "${TMP_FILE}"
echo "${BEST_IP} ${TARGET_DOMAIN} # ${MARKER}" >> "${TMP_FILE}"
cat "${TMP_FILE}" > "${HOSTS_FILE}"
rm -f "${TMP_FILE}"
```

**问题**：普通用户跑会在 `mkdir /etc/...`、`cp /etc/hosts`、尤其 `cat > /etc/hosts` 处全部 Permission denied。脚本本身没有任何 sudo 处理。

### 改造后

#### 步骤 1：注入 sudo 兼容基础设施

放在 `log()` 定义之后、备份目录创建之前：

```bash
SUDO_CMD=()
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO_CMD=(sudo -n)
    else
        log "❌ 当前用户非 root，且未找到 sudo，无法修改 ${HOSTS_FILE}"
        exit 1
    fi
fi

run_root() {
    if [ "${#SUDO_CMD[@]}" -gt 0 ]; then
        "${SUDO_CMD[@]}" "$@"
    else
        "$@"
    fi
}

run_with_fallback() {
    "$@" 2>/dev/null || run_root "$@"
}
```

#### 步骤 2：备份目录（先判断再创建，避免无谓的 sudo）

```bash
if [ ! -d "${BACKUP_DIR}" ]; then
    log "创建备份目录 ${BACKUP_DIR} ..."
    run_root mkdir -p "${BACKUP_DIR}" 2>/dev/null || { log "❌ 无法创建备份目录"; exit 1; }
fi
```

取舍：`/etc` 下目录必然要 root，用 `run_root mkdir`。加 `if [ ! -d ]` 是因为目录已存在时不必每次都触发 sudo（普通用户场景下能省一次提权）。

#### 步骤 3：备份与清理旧备份

```bash
run_root cp -a "${HOSTS_FILE}" "${BACKUP_FILE}"   # 读 /etc/hosts 普通用户可能也行，但写备份到 /etc 下要 root，统一 run_root

ls -1t "${BACKUP_DIR}"/hosts.*.bak 2>/dev/null | tail -n +$((BACKUP_RETAIN + 1)) | while IFS= read -r old; do
    run_root rm -f "${old}"     # 删 /etc 下的备份文件，要 root
done
```

#### 步骤 4：写 /etc/hosts（重点：重定向不能直接 sudo）

这是全脚本最需要小心的地方。改造前是 `grep ... > "${TMP_FILE}"` + `echo >> "${TMP_FILE}"` + `cat > "${HOSTS_FILE}"`，重定向全是普通用户 shell 做的，sudo 无效。

改造采用「tee + 兜底 sudo bash -c」双保险：

```bash
TMP_FILE="${HOSTS_FILE}.tmp.$$"   # 放 /etc 下，与目标同分区，保证 cp 覆盖原子
umask 077                          # 临时文件收紧权限

generate_new_hosts() {
    grep -v "${MARKER}" "${HOSTS_FILE}" 2>/dev/null | grep -v " ${TARGET_DOMAIN}\b" | grep -v " ${TARGET_DOMAIN} "
}

# 1) 生成临时文件：tee 由 sudo 启动，它能写 /etc
generate_new_hosts | run_root tee "${TMP_FILE}" >/dev/null 2>&1 || {
    # tee 兜底失败（极少见），改用 sudo bash -c 把整条管道+重定向塞进 root 子进程
    log "⚠️ tee 方式写入临时文件失败，改用 sudo bash 处理"
    run_root bash -c "grep -v '${MARKER}' '${HOSTS_FILE}' | grep -v ' ${TARGET_DOMAIN}\\b' | grep -v ' ${TARGET_DOMAIN} ' > '${TMP_FILE}'" || {
        log "❌ 无法生成临时文件 ${TMP_FILE}(权限不足?)"
        exit 1
    }
}

# 2) 追加新行：echo 的 >> 重定向在 root 子进程里
run_root bash -c "echo '${BEST_IP} ${TARGET_DOMAIN} # ${MARKER}' >> '${TMP_FILE}'"

# 3) 原子覆盖
run_root cp "${TMP_FILE}" "${HOSTS_FILE}" || run_root cat "${TMP_FILE}" > "${HOSTS_FILE}"

# 4) 清理
run_root rm -f "${TMP_FILE}"
```

关键点：
- 临时文件 `${HOSTS_FILE}.tmp.$$` 与 `/etc/hosts` 同在 `/etc` 分区，`cp` 覆盖是原子的。
- `generate_new_hosts` 用普通用户读 `/etc/hosts`（通常可读，`2>/dev/null` 静默失败），读出来再交给 root 的 `tee` 写——读用当前用户、写用 root，各取所需。
- `run_root bash -c '... > file'` 是处理「重定向 + sudo」的标准手段，整条命令在 root 子进程里执行，重定向也由 root 完成。

#### 步骤 5：末尾确认 grep 兜底

```bash
grep "${TARGET_DOMAIN}" "${HOSTS_FILE}" 2>/dev/null || run_root grep "${TARGET_DOMAIN}" "${HOSTS_FILE}" || true
```

读 `/etc/hosts` 一般不需要 root，但加个兜底以防极端权限设置。

## 案例二：host_set_cfbest_cron.sh

### 改造前（核心部分）

```bash
# ---------- 前置检查 ----------
if [ "$(id -u)" -ne 0 ]; then
    log "❌ 需要 root 权限"
    exit 1
fi

# ---------- 1. 立即执行 ----------
if ! curl -fsSL "${LOCAL_SCRIPT_URL}" | bash; then
    log "❌ 失败"; exit 1
fi

# ---------- 2. 写 crontab ----------
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
printf "%s\n%s %s\n" "${NEW_CRON}" "${CRON_SCHEDULE}" "${CRON_CMD}" | crontab -
```

**问题**：死 `exit 1` 让普通用户无法直接跑；`crontab` 操作的是当前用户而非 root，cron 里再跑 local 脚本改 `/etc/hosts` 又是一层权限问题。

### 改造后

#### 步骤 1：死检查换自适应

```bash
SUDO_CMD=()
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO_CMD=(sudo -n)
    else
        log "❌ 当前用户非 root，且未找到 sudo，无法修改 /etc/hosts 和 crontab"
        exit 1
    fi
fi

run_root() {
    if [ "${#SUDO_CMD[@]}" -gt 0 ]; then
        "${SUDO_CMD[@]}" "$@"
    else
        "$@"
    fi
}
```

#### 步骤 2：立即执行子脚本（普通用户要 sudo 包一层）

```bash
if [ "${#SUDO_CMD[@]}" -gt 0 ]; then
    if ! curl -fsSL "${LOCAL_SCRIPT_URL}" | "${SUDO_CMD[@]}" bash; then
        log "❌ 立即执行 local_set_bestip.sh 失败"; exit 1
    fi
else
    if ! curl -fsSL "${LOCAL_SCRIPT_URL}" | bash; then
        log "❌ 立即执行 local_set_bestip.sh 失败"; exit 1
    fi
fi
```

为什么这里显式 `sudo bash` 而不依赖子脚本内部自适应？因为 local 脚本内部用的是 `sudo -n`（非交互）。普通用户手动跑入口脚本时，第一次 `sudo` 触发密码缓存后，后续 `sudo -n` 才能免密；显式 `sudo bash` 把子脚本整体以 root 启动，子脚本内 `id -u` 就是 0，根本不走 `SUDO_CMD` 分支，最干净。

#### 步骤 3：crontab 改写 root 的

```bash
EXISTING_CRON=$(run_root crontab -l 2>/dev/null || true)
# ...
printf "%s\n%s %s\n" "${NEW_CRON}" "${CRON_SCHEDULE}" "${CRON_CMD}" | run_root crontab -
```

所有 `crontab` 调用都包 `run_root`，确保写到 **root 的 crontab**。这样 cron 以 root 身份执行，cron 命令里不用再考虑权限。

#### 步骤 4：cron 命令本身不套 sudo

```bash
CRON_CMD="curl -fsSL ${LOCAL_SCRIPT_URL} | bash >/dev/null 2>&1 ${MARKER}"
```

注意：cron 命令里是 `| bash` 而不是 `| sudo bash`。因为：
- 它写在 root 的 crontab 里，cron 以 root 身份跑，curl 和 bash 都是 root，不需要 sudo。
- 即便写在普通用户 crontab 里，也不能套 `sudo`——cron 无 tty，`sudo` 会等密码直接失败。子脚本 local_set_bestip.sh 内部自带 `sudo -n` 适配，会自己处理。

## 验证方法

改造后做了这些校验：

```bash
# 1. 语法校验
bash -n local_set_bestip.sh
bash -n host_set_cfbest_cron.sh
# 两个都输出 ✅ 语法正确

# 2. shellcheck（如有）
shellcheck local_set_bestip.sh host_set_cfbest_cron.sh

# 3. diff 备份对照
diff local_set_bestip.sh.bak.<TS> local_set_bestip.sh
diff host_set_cfbest_cron.sh.bak.<TS> host_set_cfbest_cron.sh
```

## 这个案例的通用启示

| 现象 | 通用解法 |
|---|---|
| 写系统文件 Permission denied | `tee`（sudo 启动 tee 进程）或 `run_root bash -c '... > file'`，绝不 `sudo cmd > file` |
| 改 `/etc/xxx` 怕写坏 | 临时文件（同分区）+ `umask 077` + `run_root cp` 原子覆盖 |
| crontab 改错用户的 | 明确写 root 的：所有 `crontab` 调用包 `run_root` |
| cron 里命令又卡 sudo 密码 | cron 命令不套 sudo；要么写 root crontab，要么靠子脚本内部 `sudo -n` 自适应 |
| 死 `exit 1` 太不灵活 | 换成 `SUDO_CMD` 自适应探测块 |
| 子脚本被入口脚本调用 | 入口对普通用户显式 `sudo bash 子脚本`，让子脚本以 root 启动，最省心 |
