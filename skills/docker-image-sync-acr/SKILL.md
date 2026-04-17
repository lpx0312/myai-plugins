---
name: docker-image-sync-acr
description: >-
  将 Docker 镜像同步到阿里云容器镜像服务(ACR)。支持单镜像和批量同步，自动轮询状态并返回 ACR 拉取地址。

  触发词（中文）：同步镜像、镜像同步、docker镜像同步、ACR同步、阿里云镜像同步、同步到ACR、镜像搬运、
  镜像迁移、把xxx镜像同步、帮我同步、拉取镜像到ACR、同步nginx、同步redis、同步某个镜像、镜像转存、
  Docker Hub到阿里云、海外镜像同步、gcr.io同步、quay.io同步、ghcr.io同步、k8s镜像同步、gcr镜像、
  quay镜像、ghcr镜像、docker.io镜像同步。

  触发词（英文）：sync docker image、sync image to acr、image sync、mirror docker image、
  docker image sync、sync nginx、sync redis、sync to aliyun、acr sync、container image sync。

  使用场景：(1) 用户想将 Docker Hub/Google Container Registry/Quay/GitHub Container Registry
  等海外镜像同步到阿里云 ACR；(2) 用户提到"同步"和"镜像"的组合；(3) 用户需要获取镜像的 ACR 拉取地址；
  (4) 用户提到"ACR"、"阿里云镜像"相关操作；(5) 批量同步多个镜像。
---

# Docker 镜像同步到 ACR

## 环境变量配置（必须）

执行前需配置以下环境变量：

```bash
export IMAGE_SYNC_API_BASE="http://192.168.0.180:10003/api/v1"
export IMAGE_SYNC_USERNAME="XXXX"
export IMAGE_SYNC_PASSWORD="XXXX"
```

**Windows (PowerShell):**
```powershell
$env:IMAGE_SYNC_API_BASE="http://192.168.0.180:10003/api/v1"
$env:IMAGE_SYNC_USERNAME="XXXX"
$env:IMAGE_SYNC_PASSWORD="XXXX"
```

> 建议将这些配置添加到 `~/.bashrc` 或系统环境变量中持久化。

## 工作流程

### 1. 登录获取 Token

```bash
TOKEN=$(curl -sS -X POST "$IMAGE_SYNC_API_BASE/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$IMAGE_SYNC_USERNAME\",\"password\":\"$IMAGE_SYNC_PASSWORD\"}" | jq -r '.token')
```

Token 有效期 24 小时，后续请求需携带 `Authorization: Bearer $TOKEN`。

### 2. 提交同步任务

**单镜像：**
```bash
curl -sS -X POST "$IMAGE_SYNC_API_BASE/sync/submit" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"images":["nginx:latest"],"architecture":"amd64"}'
```

**批量镜像：**
```bash
curl -sS -X POST "$IMAGE_SYNC_API_BASE/sync/batch" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "images": [
      {"source_image": "nginx:latest", "architecture": "amd64"},
      {"source_image": "redis:alpine", "architecture": "amd64"}
    ],
    "max_concurrent": 3
  }'
```

返回 `task_id` 用于查询状态。

### 3. 轮询状态获取 ACR 地址

```bash
# 等待 3-10 秒后首次查询，之后每 5-15 秒轮询一次
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$IMAGE_SYNC_API_BASE/sync/status/$TASK_ID" \
  | jq '.images.records[] | {source:.original_image, acr:.acr_image, status:.sync_status}'
```

**状态说明：**
- 任务状态 (`status`): `pending` → `running` → `completed`/`failed`/`partial_success`
- 镜像状态 (`sync_status`): `pending` → `syncing` → `success`/`failed`
- **ACR 地址**: `acr_image` 字段，同步成功后才有值

### 4. 完整示例脚本

```bash
#!/bin/bash
# 同步镜像并获取 ACR 地址

# 1. 登录
TOKEN=$(curl -sS -X POST "$IMAGE_SYNC_API_BASE/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$IMAGE_SYNC_USERNAME\",\"password\":\"$IMAGE_SYNC_PASSWORD\"}" | jq -r '.token')

# 2. 提交
TASK_ID=$(curl -sS -X POST "$IMAGE_SYNC_API_BASE/sync/submit" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"images":["nginx:latest"],"architecture":"amd64"}' | jq -r '.task_id')

echo "Task ID: $TASK_ID"

# 3. 轮询（最多 30 分钟）
for i in {1..120}; do
  sleep 15
  RESULT=$(curl -sS -H "Authorization: Bearer $TOKEN" \
    "$IMAGE_SYNC_API_BASE/sync/status/$TASK_ID")
  STATUS=$(echo "$RESULT" | jq -r '.status')

  if [[ "$STATUS" == "completed" || "$STATUS" == "failed" || "$STATUS" == "partial_success" ]]; then
    echo "$RESULT" | jq '.images.records[] | {source:.original_image, acr:.acr_image, status:.sync_status}'
    break
  fi
  echo "[$i] Status: $STATUS, waiting..."
done
```

## API 参考

| 接口 | 方法 | 说明 |
|------|------|------|
| `/auth/login` | POST | 登录获取 Token |
| `/sync/submit` | POST | 单镜像同步 |
| `/sync/batch` | POST | 批量同步 |
| `/sync/status/:taskId` | GET | 查询任务状态 |

## 注意事项

- 所有接口需要 JWT 认证（除登录接口外）
- 同步为异步执行，需轮询状态
- 架构支持 `amd64` 和 `arm64`
- 废弃接口：`/sync/batch/status/:taskId`（勿用）
