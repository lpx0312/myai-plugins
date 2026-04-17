# 证书格式转换指南

## 概述

证书格式转换是 SSL/TLS 工作中的常见需求。本指南涵盖 PEM、DER、PKCS12、JKS、PKCS8 等格式的互转。

---

## 格式说明

| 格式 | 扩展名 | 说明 |
|-----|-------|------|
| PEM | .pem, .crt, .cer | Base64编码的DER，带头部 `-----BEGIN CERTIFICATE-----` |
| DER | .der, .cer | 二进制编码，不带头部 |
| PKCS12 | .p12, .pfx | 可包含证书+私钥+CA链，支持密码保护 |
| JKS | .jks | Java专用，可包含多个证书+私钥 |
| PKCS8 | .key, .pem | 私钥格式，支持加密 |

---

## PEM 格式操作

### PEM 查看与提取

```bash
# 查看PEM证书内容
cat cert.pem

# 提取证书信息
openssl x509 -in cert.pem -text -noout

# 从PEM文件中提取单个证书
# PEM可能包含多张证书（证书链）
awk 'BEGIN{c=0} /-----BEGIN CERTIFICATE-----/{c=1} c{print} /-----END CERTIFICATE-----/{if(c) exit}' \
  cert-chain.pem > first-cert.pem
```

### PEM 证书链合并/拆分

```bash
# 合并证书（服务器证书在前，中间CA在后，根CA可选）
cat server.crt intermediate.crt > chain.pem

# 拆分证书链
# 方法1: 使用awk（见上）
# 方法2: 使用OpenSSL
csplit -f cert- -b %02d.pem chain.pem \
  '/-----BEGIN CERTIFICATE-----/' '{*}'
```

---

## PEM ↔ DER 转换

### PEM → DER

```bash
# 单个证书
openssl x509 -in cert.pem -outform DER -out cert.der

# 批量转换
for f in *.pem; do
  openssl x509 -in "$f" -outform DER -out "${f%.pem}.der"
done
```

### DER → PEM

```bash
# 单个证书
openssl x509 -in cert.der -inform DER -outform PEM -out cert.pem

# 批量转换
for f in *.der; do
  openssl x509 -in "$f" -inform DER -outform PEM -out "${f%.der}.pem"
done
```

---

## PEM ↔ PKCS12 转换

### PEM + 私钥 → PKCS12

```bash
# 基础转换
openssl pkcs12 -export \
  -in cert.pem \
  -inkey key.pem \
  -out cert.p12

# 包含CA证书
openssl pkcs12 -export \
  -in cert.pem \
  -inkey key.pem \
  -certfile ca-chain.pem \
  -out cert.p12

# 设置名称和密码
openssl pkcs12 -export \
  -in cert.pem \
  -inkey key.pem \
  -out cert.p12 \
  -name "My Certificate" \
  -password pass:mypassword

# 同时包含客户端CA（用于双向认证）
openssl pkcs12 -export \
  -in client.crt \
  -inkey client.key \
  -certfile ca.crt \
  -out client.p12
```

### PKCS12 → PEM

```bash
# 导出所有内容（证书+私钥+CA）
openssl pkcs12 -in cert.p12 -nodes -out all.pem

# 只导出证书（不含私钥）
openssl pkcs12 -in cert.p12 -nokeys -out cert.pem

# 只导出私钥
openssl pkcs12 -in cert.p12 -nocerts -nodes -out key.pem

# 只导出CA证书
openssl pkcs12 -in cert.p12 -nokeys -cacerts -out ca.pem

# 指定密码
openssl pkcs12 -in cert.p12 -password pass:mypassword -nodes -out all.pem
```

### PKCS12 验证与查看

```bash
# 查看PKCS12内容
openssl pkcs12 -in cert.p12 -info -noout

# 验证证书与私钥匹配
openssl pkcs12 -in cert.p12 -nodes | \
  openssl x509 -noout -modulus | openssl md5
```

---

## JKS ↔ PKCS12 转换

### 使用 keytool

```bash
# PKCS12 → JKS
keytool -importkeystore \
  -srckeystore cert.p12 \
  -srcstoretype PKCS12 \
  -destkeystore keystore.jks \
  -deststoretype JKS

# JKS → PKCS12
keytool -importkeystore \
  -srckeystore keystore.jks \
  -srcstoretype JKS \
  -destkeystore cert.p12 \
  -deststoretype PKCS12

# 指定密码
keytool -importkeystore \
  -srckeystore cert.p12 -srcstoretype PKCS12 \
  -destkeystore keystore.jks -deststoretype JKS \
  -srcstorepass mysrcpass \
  -deststorepass mydestpass
```

### 导入证书到现有JKS

```bash
# 导入服务器证书（需要已有私钥条目）
keytool -importcert \
  -alias server \
  -file server.crt \
  -keystore keystore.jks

# 导入CA证书到truststore
keytool -importcert \
  -alias rootca \
  -file ca.crt \
  -keystore truststore.jks \
  -trustcacerts
```

---

## 私钥格式转换

### 传统格式 ↔ PKCS8

```bash
# 传统格式 → PKCS8
openssl pkcs8 -topk8 \
  -in traditional.key \
  -out pkcs8.key \
  -nocrypt

# PKCS8 → 传统格式
openssl pkcs8 -in pkcs8.key \
  -nocrypt -out traditional.key

# 加密PKCS8私钥
openssl pkcs8 -topk8 \
  -in traditional.key \
  -out encrypted-pkcs8.key \
  -v1 PBE-SHA1-3DES
```

### RSA ↔ EC 私钥

```bash
# 生成EC私钥
openssl ecparam -genkey -name prime256v1 -out ec.key

# EC → PKCS8
openssl pkcs8 -topk8 -in ec.key -out ec-pkcs8.key -nocrypt

# 查看EC私钥参数
openssl ec -in ec.key -text -noout
```

---

## 证书链处理

### 合并证书链

```bash
# 方式1: 直接cat
cat server.crt intermediate.crt > chain.pem

# 方式2: 使用OpenSSL确保格式正确
# 1. 先导出PEM格式
openssl pkcs12 -in server.p12 -nokeys -out server.pem
openssl pkcs12 -in server.p12 -nocerts -nodes -out key.pem
openssl pkcs12 -in server.p12 -nokeys -cacerts -out ca.pem

# 2. 合并
cat server.pem ca.pem > full-chain.pem
```

### 提取证书链中的每个证书

```bash
# 方法1: 使用sed
sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' chain.pem > certs.txt
csplit -f cert- certs.txt '/-----BEGIN CERTIFICATE-----/' '{*}'

# 方法2: 使用awk（更可靠）
awk 'BEGIN {c=0} /-----BEGIN CERTIFICATE-----/{c=1; n++} c{print > ("cert-" n ".pem")} /-----END CERTIFICATE-----/{close("cert-" n ".pem")}' chain.pem

# 方法3: 使用OpenSSL + storeutl (OpenSSL 1.1.1+)
openssl storeutl -noout -text -certs chain.pem
```

### 验证证书链

```bash
# 完整验证
openssl verify -CAFile root-ca.crt -untrusted intermediate.crt server.crt

# 简化验证（如果中间证书已在 CAFile）
openssl verify -CAFile ca-bundle.crt server.crt

# 验证并显示证书链
openssl verify -show_chain -CAFile ca-bundle.crt server.crt
```

---

## 远程证书导出

### 导出远程服务器证书

```bash
# 导出单个证书
echo | openssl s_client -connect example.com:443 \
  -servername example.com | \
  openssl x509 > remote.crt

# 导出完整证书链
echo | openssl s_client -connect example.com:443 \
  -showcerts | \
  sed -n '/-----BEGIN/,/-----END/p' > chain.pem

# 导出为DER格式
echo | openssl s_client -connect example.com:443 | \
  openssl x509 -outform DER -out remote.der
```

---

## 常用场景脚本

### 场景1: Nginx 单向 HTTPS 配置

```bash
#!/bin/bash
# prepare-nginx-ssl.sh

DOMAIN="example.com"
OUTPUT_DIR="/etc/nginx/ssl"

# 生成私钥
openssl genrsa -out "$OUTPUT_DIR/$DOMAIN.key" 2048

# 生成CSR
openssl req -new -key "$OUTPUT_DIR/$DOMAIN.key" \
  -out "$OUTPUT_DIR/$DOMAIN.csr" \
  -subj "/C=CN/L=Beijing/O=MyOrg/CN=$DOMAIN"

# 提交CSR到CA，获取证书后：
# 将证书和密钥放入nginx配置
# ssl_certificate /etc/nginx/ssl/example.com.crt;
# ssl_certificate_key /etc/nginx/ssl/example.com.key;
```

### 场景2: Java mTLS 环境准备

```bash
#!/bin/bash
# prepare-java-mtls.sh

KEYSTORE_PASS="changeit"

# 1. 转换服务器证书为PKCS12
openssl pkcs12 -export \
  -in server.crt \
  -inkey server.key \
  -out server.p12 \
  -password pass:$KEYSTORE_PASS

# 2. 创建TrustStore并导入CA
keytool -importcert \
  -alias rootca \
  -file ca.crt \
  -keystore truststore.jks \
  -storepass $KEYSTORE_PASS \
  -trustcacerts -noprompt

# 3. 验证
keytool -list -keystore server.p12 -storetype PKCS12 \
  -storepass $KEYSTORE_PASS
keytool -list -keystore truststore.jks \
  -storepass $KEYSTORE_PASS
```

### 场景3: 浏览器客户端证书准备

```bash
#!/bin/bash
# prepare-browser-cert.sh

USER_CN="john.doe"

# 1. 从XCA导出客户端证书为PKCS12
# 或手动转换：
openssl pkcs12 -export \
  -in "$USER_CN.crt" \
  -inkey "$USER_CN.key" \
  -out "$USER_CN.p12" \
  -name "$USER_CN"

# 2. 用户需要安装：
#    - $USER_CN.p12 (客户端证书)
#    - root-ca.crt (根CA证书)
```

---

## 格式验证命令

```bash
# 验证PEM格式
openssl x509 -in cert.pem -text -noout && echo "Valid PEM"

# 验证DER格式
openssl x509 -in cert.der -inform DER -text -noout && echo "Valid DER"

# 验证PKCS12
openssl pkcs12 -in cert.p12 -nodes -noout && echo "Valid PKCS12"

# 验证私钥
openssl rsa -in key.pem -check -noout && echo "Valid RSA Key"
openssl ec -in ec.key -check -noout && echo "Valid EC Key"

# 验证私钥与证书匹配
openssl x509 -in cert.pem -noout -modulus | md5sum
openssl rsa -in key.pem -noout -modulus | md5sum
# 两个输出应相同
```

---

## 工具对比

| 工具 | 适用场景 | 优点 | 缺点 |
|-----|---------|------|------|
| OpenSSL | 大部分格式转换 | 通用、强大 | 命令复杂 |
| keytool | JKS/PKCS12/Java相关 | Java原生 | 功能有限 |
| XCA | 证书创建管理 | GUI友好 | 不能批量转换 |
| openssl pkcs12 | PKCS12相关 | 灵活 | - |

---

## 注意事项

1. **密码保护**: PKCS12 和加密私钥必须设置密码
2. **证书链顺序**: 合并时注意顺序（服务器证书在前）
3. **编码格式**: Windows 通常用 DER，Linux 用 PEM
4. **私钥权限**: 私钥文件权限应设为 600
5. **备份**: 转换前先备份原始文件
