# Nginx mTLS 配置指南

## 概述

mTLS (Mutual TLS) 双向认证要求客户端和服务器互相验证证书，实现更安全的通信。

**典型应用场景：**
- API网关安全访问
- 内网服务间安全通信
- 企业内部系统访问控制

---

## 完整配置模板

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    # ==================== 服务器证书配置 ====================
    # 服务器证书文件 (包含中间证书)
    ssl_certificate /etc/nginx/ssl/server.crt;

    # 服务器私钥文件
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # ==================== 客户端认证配置 ====================
    # CA证书文件 (用于验证客户端证书)
    ssl_client_certificate /etc/nginx/ssl/ca.crt;

    # 启用客户端证书验证
    ssl_verify_client on;

    # 验证深度 (0=只验证客户端证书, 1=验证客户端+一级中间CA, 2+=更深)
    ssl_verify_depth 2;

    # ==================== SSL协议和加密配置 ====================
    # 启用TLS 1.2和1.3，禁用低版本
    ssl_protocols TLSv1.2 TLSv1.3;

    # 优先使用服务器端的加密算法
    ssl_prefer_server_ciphers on;

    # 加密算法套件
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:
                ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

    # ==================== 会话优化 ====================
    # 启用会话缓存
    ssl_session_cache shared:SSL:10m;

    # 会话超时时间
    ssl_session_timeout 1d;

    # 启用TLS会话票据
    ssl_session_tickets off;

    # ==================== 其他安全头 ====================
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # ==================== 请求处理 ====================
    location / {
        # 客户端证书信息变量
        # $ssl_client_s_dn: 客户端证书Subject
        # $ssl_client_cert: 客户端证书PEM格式
        # $ssl_client_verify: 验证结果 (SUCCESS/FAILED/NONE)

        # 可根据客户端证书做访问控制
        if ($ssl_client_verify != SUCCESS) {
            return 403;
        }

        proxy_pass http://backend:8080;
        proxy_set_header X-Client-Cert $ssl_client_cert;
        proxy_set_header X-Client-DN $ssl_client_s_dn;
    }
}
```

---

## 配置项详解

### ssl_client_certificate

**说明：** 指定受信任的CA证书文件，用于验证客户端证书

**要求：**
- 必须是PEM格式
- 可以包含多个CA证书（按信任链顺序）
- 客户端证书必须由这些CA之一签发

```nginx
# 单一CA
ssl_client_certificate /etc/nginx/ssl/ca.crt;

# CA证书链（根CA + 中间CA）
ssl_client_certificate /etc/nginx/ssl/ca-chain.crt;
```

### ssl_verify_client

| 值 | 说明 |
|----|------|
| `off` | 不验证客户端证书（默认） |
| `on` | 强制验证客户端证书，验证失败拒绝连接 |
| `optional` | 可选验证，失败仍允许连接（通过 `$ssl_client_verify` 判断） |
| `optional_no_ca` | 可选但不验证证书有效性 |

```nginx
# 强制验证
ssl_verify_client on;

# 可选验证（用于测试）
ssl_verify_client optional;
```

### ssl_verify_depth

设置验证证书链的最大深度：

| 深度 | 适用场景 |
|-----|---------|
| 0 | 客户端证书直接由受信任CA签发（无中间CA） |
| 1 | 受信任CA → 中间CA → 客户端证书 |
| 2 | 受信任CA → 中间CA1 → 中间CA2 → 客户端证书 |

---

## 获取客户端证书信息

### 可用变量

| 变量 | 说明 | 示例 |
|-----|------|------|
| `$ssl_client_s_dn` | 客户端证书Subject | `/CN=john/O=MyOrg` |
| `$ssl_client_s_dn_escaped` | URL转义的Subject | `%2FCN%3Djohn` |
| `$ssl_client_i_dn` | 签发者DN | `/CN=My CA/O=MyOrg` |
| `$ssl_client_cert` | 完整PEM证书 | `-----BEGIN CERTIFICATE-----...` |
| `$ssl_client_verify` | 验证结果 | `SUCCESS`, `FAILED:...`, `NONE` |
| `$ssl_client_serial` | 证书序列号 | `1234ABCD...` |

### 提取特定字段

```nginx
location /api {
    # 通过map提取CN
    map $ssl_client_s_dn $client_cn {
        ~CN=([^,]+) $1;
    }

    proxy_set_header X-Client-CN $client_cn;
    proxy_set_header X-Client-Cert $ssl_client_cert;
}
```

---

## 实际应用示例

### 示例1：API访问控制

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_client_certificate /etc/nginx/ssl/clients.ca.crt;
    ssl_verify_client on;
    ssl_verify_depth 1;

    # 允许的客户端CN列表
    map $ssl_client_s_dn $allowed_client {
        default 0;
        "~CN=app-server-01" 1;
        "~CN=app-server-02" 1;
        "~CN=mobile-client" 1;
    }

    location / {
        if ($allowed_client = 0) {
            return 403;
        }
        proxy_pass http://backend;
    }
}
```

### 示例2：可选客户端认证（兼容两种模式）

```nginx
server {
    listen 443 ssl;
    server_name api.example.com;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_client_certificate /etc/nginx/ssl/ca.crt;
    ssl_verify_client optional;  # 可选，但不验证CA

    location / {
        # 有证书走mTLS
        if ($ssl_client_verify = SUCCESS) {
            proxy_set_header X-Client-CN $ssl_client_s_dn;
            set $auth_mode "mtls";
        }

        # 无证书走API Key
        if ($ssl_client_verify != SUCCESS) {
            set $auth_mode "apikey";
        }

        # 根据认证方式处理
        proxy_pass http://backend;
    }
}
```

---

## 测试命令

### 验证Nginx配置

```bash
# 检查配置语法
nginx -t

# 检查配置并显示
nginx -T
```

### 使用OpenSSL测试

```bash
# 测试不带客户端证书
openssl s_client -connect api.example.com:443

# 测试带客户端证书
openssl s_client -connect api.example.com:443 \
  -cert client.crt -key client.key

# 测试带完整证书链的客户端证书
openssl s_client -connect api.example.com:443 \
  -cert client.crt -key client.key \
  -CAfile clients.ca.crt

# 显示证书链
openssl s_client -connect api.example.com:443 \
  -cert client.crt -key client.key \
  -showcerts
```

### 使用curl测试

```bash
# 需要将客户端证书转为PEM
curl --cert client.crt --key client.key \
     --cacert ca.crt \
     https://api.example.com/api

# 使用PKCS12格式
curl --cert-type P12 --cert client.p12:password \
     --cacert ca.crt \
     https://api.example.com/api
```

---

## 证书格式要求

### 服务器端证书

```bash
# 服务器证书应包含完整证书链（可选）
cat server.crt intermediate.crt > server.chain.crt

# Nginx配置
ssl_certificate /etc/nginx/ssl/server.chain.crt;
```

### 客户端CA证书

```bash
# 如果客户端证书有中间CA，需要将CA链合并
cat root-ca.crt intermediate.crt > clients.ca.crt

# Nginx配置
ssl_client_certificate /etc/nginx/ssl/clients.ca.crt;
```

---

## 性能优化

### 启用OCSP Stapling

```nginx
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
ssl_trusted_certificate /etc/nginx/ssl/ca.crt;
```

### 使用硬件加速

```nginx
ssl_engine aesni;  # 如果CPU支持AES-NI
```

---

## 常见问题排查

### 1. 客户端证书验证失败

```bash
# 检查客户端证书是否由正确CA签发
openssl verify -CAFile clients.ca.crt client.crt

# 检查证书链完整性
openssl s_client -connect api.example.com:443 -showcerts \
  -cert client.crt -key client.key
```

### 2. 查看详细错误日志

```nginx
# 临时添加到server块
ssl_verify_client error;
```

### 3. 调试模式

```bash
# 查看OpenSSL握手详情
openssl s_client -connect api.example.com:443 \
  -cert client.crt -key client.key -debug
```
