---
name: cert-manager
description: >-
  SSL证书管理助手，简化 XCA、OpenSSL、Nginx mTLS、Maven/Java 证书配置工作流。

  触发场景：
  - 使用XCA创建根CA、中间CA、服务器证书、客户端证书
  - Nginx HTTPS双向认证(SSL证书配置)
  - Maven/Gradle项目配置SSL证书
  - Java KeyStore/JKS/PKCS12证书格式转换
  - keytool Java密钥库管理
  - 检查证书有效期、验证证书链
  - OpenSSL命令操作证书（查看/验证/转换/签发）
  - 证书不受信任、SSL握手失败等问题排查
  - PEM/DER/PKCS12/PKCS8格式转换

  触发词（中文）：证书、SSL、TLS、CA、根证书、中间CA、证书链、XCA、OpenSSL、keytool、
  mTLS、双向认证、客户端证书、服务器证书、nginx ssl、https证书、keystore、truststore、
  jks、pkcs12、pkcs8、pem、der、cer、crt、私钥、CSR、证书签名请求、证书格式转换、
  证书过期、证书验证、证书不受信任、SAN、subject alternate name、IP证书

  触发词（英文）：certificates、ssl、tls、ca、root ca、intermediate ca、certificate chain、
  xca、openssl、keytool、mtls、mutual tls、client-cert、server-cert、client certificate、
  server certificate、nginx ssl、https、keystore、truststore、jks、pkcs12、pkcs8、pem、
  der、cer、crt、private key、csr、certificate signing request、certificate format conversion、
  certificate expiration、certificate verification、untrusted certificate、san、subject alt name、ip certificate
---

# cert-manager: SSL证书管理助手

## Overview

cert-manager 提供标准化的SSL/TLS证书管理工作流，覆盖从证书创建到部署的全流程。

**核心功能：**
- XCA 可视化证书创建（根CA/服务器证书/客户端证书）
- OpenSSL 命令行操作
- Nginx mTLS 双向认证配置
- Java KeyStore/Maven SSL配置
- 证书格式转换（PEM/DER/P12/JKS）
- 证书有效期批量检查

---

## Quick Commands

### 查看证书信息

```bash
# 查看证书详情
openssl x509 -in cert.pem -text -noout

# 查看证书有效期
openssl x509 -in cert.pem -dates -noout

# 查看证书Subject和Issuer
openssl x509 -in cert.pem -subject -issuer -noout

# 验证证书链
openssl verify -CAFile ca-bundle.crt cert.pem

# 远程服务器证书检查
echo | openssl s_client -connect example.com:443 -servername example.com | openssl x509 -dates -noout
```

### 证书格式转换

```bash
# PEM -> PKCS12
openssl pkcs12 -export -in cert.pem -inkey key.pem -certfile ca.pem -out cert.p12

# PKCS12 -> PEM
openssl pkcs12 -in cert.p12 -nodes -out cert.pem

# PEM -> DER
openssl x509 -in cert.pem -outform DER -out cert.der

# DER -> PEM
openssl x509 -in cert.der -inform DER -outform PEM -out cert.pem
```

### 证书有效期检查

```bash
# 使用Python脚本批量检查（支持本地文件和远程URL）
python cert-manager/scripts/check_cert_expiry.py --input certs.txt
python cert-manager/scripts/check_cert_expiry.py --url https://example.com --warn 30
```

---

## Core Workflows

### 1. XCA 创建证书

详见：[references/xca-workflow.md](references/xca-workflow.md)

**流程概述：**
1. 创建根CA（自签名）
2. 创建服务器证书（由根CA签发）
3. 创建客户端证书（由根CA签发）
4. 导出所需格式

### 2. OpenSSL 命令操作

详见：[references/openssl-commands.md](references/openssl-commands.md)

涵盖：证书查看、验证、私钥操作、CSR生成、证书链处理

### 3. Nginx mTLS 配置

详见：[references/nginx-mtls.md](references/nginx-mtls.md)

**模板预览：**
```nginx
server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate /path/to/server.crt;
    ssl_certificate_key /path/to/server.key;
    ssl_client_certificate /path/to/ca.crt;
    ssl_verify_client on;
    ssl_verify_depth 2;
}
```

### 4. Java/Maven SSL 配置

详见：[references/java-keystore.md](references/java-keystore.md)

涵盖：keytool命令、Maven settings.xml配置、Java代码SSL配置

### 5. 证书格式转换

详见：[references/format-conversion.md](references/format-conversion.md)

支持：PEM/DER/P12/JKS/PKCS8 互转

---

## 常用场景

### 场景1：创建自签名服务器证书

```bash
# 1. 生成私钥
openssl genrsa -out server.key 2048

# 2. 生成CSR
openssl req -new -key server.key -out server.csr

# 3. 自签名
openssl x509 -req -in server.csr -signkey server.key -out server.crt -days 365

# 4. 转为PKCS12（用于Java/Keystore）
openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12
```

### 场景2：配置Nginx双向认证

1. 使用XCA创建根CA和客户端证书
2. 参考 [references/nginx-mtls.md](references/nginx-mtls.md) 配置Nginx
3. 分发客户端证书(.p12)给用户安装

### 场景3：检查证书有效期

```bash
# 单个文件
python cert-manager/scripts/check_cert_expiry.py --file server.crt

# 批量检查（文件列表）
python cert-manager/scripts/check_cert_expiry.py --input certs.txt

# 远程URL检查
python cert-manager/scripts/check_cert_expiry.py --url https://example.com --warn 30
```

---

## 文件结构

```
cert-manager/
├── SKILL.md                    # 本文件
├── scripts/
│   └── check_cert_expiry.py   # 证书有效期批量检查脚本
└── references/
    ├── openssl-commands.md     # OpenSSL 命令速查
    ├── nginx-mtls.md           # Nginx mTLS 配置模板
    ├── xca-workflow.md         # XCA 使用指南
    ├── java-keystore.md         # Java/Maven SSL配置
    └── format-conversion.md    # 证书格式转换指南
```
