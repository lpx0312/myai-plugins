---
name: file-timestamp
description: 修改文件的时间戳（创建时间、修改时间、访问时间），支持本地路径和 UNC 网络共享路径。当用户要求更改/设置/伪造文件的创建时间、修改时间、访问时间、时间戳（如"把修改时间改成 20260810 08:29"、"creation time"、"modified time"、"timestamp"）时使用，即使用户只是随口提到文件时间不对要改。
---

# 修改文件时间戳（Windows）

把文件的创建时间（CreationTime）、修改时间（LastWriteTime）设置为用户指定的值。LastAccessTime 跟随修改时间一并设置。支持本地路径和 UNC 网络共享路径（如 `\\192.168.0.180\dsm_old`）。

## 两种定位文件的方式

bundled 脚本 `scripts/set-file-time.ps1` 支持两种方式，优先用方式一：

1. **`-FullPath`（首选）**：直接传文件完整路径。中文路径没问题——已实测从 Git Bash 命令行传参不会乱码（命令行参数以 UTF-16 传递）。
2. **`-Root` + `-Pattern`（模糊搜索备用）**：用户只给了大概位置和文件名片段时使用，脚本从 Root 递归搜索匹配 Pattern 的文件，要求恰好匹配 1 个。

约束：**不要把中文写进任何 `.ps1` 脚本文件内部**。PowerShell 5.1 把无 BOM 的 UTF-8 脚本按 ANSI/GBK 解析，脚本文件里的中文路径会乱码；命令行参数则安全。

## 步骤

1. 从用户输入中解析：目标文件路径（或位置+文件名片段）、创建时间、修改时间。
   - 用户可能写 `20260810 08:29:00`，归一化为 `yyyy-MM-dd HH:mm:ss`
   - 用户只要求改修改时间就只传 `-Modified`；只改创建时间就只传 `-Created`。没提到的不要改
   - 用户没说清哪个时间对应哪个值时，先确认再执行
2. 通过 Bash 调用脚本（注意 Git Bash 下路径反斜杠的转义，建议整条命令用单引号包裹）：

```bash
# 方式一：完整路径
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/set-file-time.ps1" -FullPath '\\192.168.0.180\dsm_old\报表20260810.xlsx' -Created '2026-08-10 08:23:00' -Modified '2026-08-10 08:29:00'

# 方式二：根目录 + 通配符递归搜索
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill目录>/scripts/set-file-time.ps1" -Root '\\192.168.0.180\dsm_old' -Pattern '*20260810.xlsx' -Created '2026-08-10 08:23:00' -Modified '2026-08-10 08:29:00'
```

3. 检查脚本输出确认结果：
   - `FILE NOT FOUND`：核对路径拼写；若是 UNC 路径可用 `ls '//host/share/目录/'` 先确认文件存在。模糊搜索模式则换更宽的 Root 或 Pattern 重试
   - `MULTIPLE MATCHES`：把 Pattern 收窄（加更多文件名片段）后重试
   - 成功时会打印文件完整路径和修改后的三个时间戳，向用户原样汇报

## 脚本行为

脚本（ASCII only）按上述两种方式定位文件：FullPath 模式下文件必须恰好存在；Root+Pattern 模式递归搜索，要求恰好匹配 1 个。定位成功才执行修改并回显结果；失败时返回错误码 1（未找到）/2（多个匹配）/3（参数缺失），不做任何修改。设置失败通常意味着对共享目录没有写权限，如实向用户报告。
