# OpenSSL 命令速查

## 证书查看命令

### 基本信息查看

```bash
# 查看证书详情
openssl x509 -in cert.pem -text -noout

# 查看证书序列号
openssl x509 -in cert.pem -serial -noout

# 查看证书Subject
openssl x509 -in cert.pem -subject -noout

# 查看证书Issuer
openssl x509 -in cert.pem -issuer -noout

# 查看证书指纹 (SHA256)
openssl x509 -in cert.pem -fingerprint -sha256 -noout

# 查看证书指纹 (MD5)
openssl x509 -in cert.pem -fingerprint -md5 -noout
```

### 日期信息

```bash
# 查看证书有效期
openssl x509 -in cert.pem -dates -noout

# 输出示例:
# notBefore=Jan 15 00:00:00 2024 GMT
# notAfter=Jan 15 00:00:00 2025 GMT
```

### 证书链查看

```bash
# 查看完整证书链
openssl s_client -connect example.com:443 -showcerts </dev/null

# 查看证书链中的所有证书
openssl s_client -connect example.com:443 -showcerts </dev/null | \
  grep -A 100 "Certificate chain"
```

---

## 证书验证命令

### 基础验证

```bash
# 验证证书（需要CA证书）
openssl verify -CAFile ca-bundle.crt server.crt

# 验证完整证书链
openssl verify -CAFile ca-bundle.crt -untrusted intermediate.crt server.crt

# 验证并显示验证路径
openssl verify -CAFile ca-bundle.crt -show_chain server.crt
```

### 远程服务器验证

```bash
# 检查远程服务器证书
echo | openssl s_client -connect example.com:443 -servername example.com | \
  openssl x509 -dates -noout

# 获取完整证书链
echo | openssl s_client -connect example.com:443 -showcerts

# 测试TLS版本
openssl s_client -connect example.com:443 -tls1_2
openssl s_client -connect example.com:443 -tls1_3

# 测试SSL连接并查看cipher
openssl s_client -connect example.com:443
```

---

## CSR (证书签名请求)

### 生成CSR

```bash
# 交互式生成CSR
openssl req -new -key server.key -out server.csr

# 非交互式生成CSR
openssl req -new -key server.key -out server.csr \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=MyOrg/OU=IT/CN=example.com"

# 查看CSR内容
openssl req -in server.csr -text -noout
```

### 使用现有CSR重新签发

```bash
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365
```

### 使用SAN（含IP）生成证书

创建带 Subject Alternative Name 的证书，需要使用 OpenSSL 配置文件：

```bash
# 1. 创建扩展配置文件 san.cnf
cat > san.cnf << 'EOF'
[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = example.com
DNS.2 = *.example.com
IP.1 = 192.168.1.100
IP.2 = 10.0.0.1
EOF

# 2. 使用配置文件生成CSR
openssl req -new -key server.key -out server.csr -config san.cnf

# 3. 使用配置文件签发证书
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365 -extensions v3_req \
  -extfile san.cnf

# 4. 验证证书SAN
openssl x509 -in server.crt -text -noout | grep -A 1 "Subject Alternative Name"
```

---

## 私钥操作

### 生成私钥

```bash
# 生成RSA私钥 (2048位)
openssl genrsa -out server.key 2048

# 生成RSA私钥 (4096位)
openssl genrsa -out server.key 4096

# 生成RSA私钥并加密
openssl genrsa -aes256 -out server.key 2048

# 生成EC私钥
openssl ecparam -genkey -name prime256v1 -out server.key
```

### 私钥转换

```bash
# RSA私钥 -> PKCS8格式
openssl pkcs8 -topk8 -in server.key -out server_pkcs8.key -nocrypt

# PKCS8 -> 传统格式
openssl pkcs8 -in server_pkcs8.key -nocrypt -out server.key

# 查看私钥信息
openssl rsa -in server.key -text -noout

# 验证私钥与证书匹配
openssl x509 -in cert.pem -noout -modulus | md5sum
openssl rsa -in server.key -noout -modulus | md5sum
```

### 私钥加密/解密

```bash
# 加密私钥
openssl rsa -in server.key -aes256 -out server.encrypted.key

# 解密私钥
openssl rsa -in server.encrypted.key -out server.key
```

---

## 证书格式转换

### PEM/DER转换

```bash
# PEM -> DER
openssl x509 -in cert.pem -outform DER -out cert.der
openssl x509 -in cert.pem -outform DER -out cert.cer

# DER -> PEM
openssl x509 -in cert.der -inform DER -outform PEM -out cert.pem
openssl x509 -in cert.cer -inform DER -outform PEM -out cert.pem
```

### PEM -> PKCS12

```bash
# 单证书 + 私钥
openssl pkcs12 -export -in cert.pem -inkey key.pem -out cert.p12

# 包含CA证书链
openssl pkcs12 -export -in cert.pem -inkey key.pem \
  -certfile ca-bundle.pem -out cert.p12

# 设置PKCS12别名
openssl pkcs12 -export -in cert.pem -inkey key.pem \
  -out cert.p12 -name "My Certificate"
```

### PKCS12 -> PEM

```bash
# 导出所有内容
openssl pkcs12 -in cert.p12 -nodes -out all.pem

# 只导出证书
openssl pkcs12 -in cert.p12 -nokeys -out cert.pem

# 只导出私钥
openssl pkcs12 -in cert.p12 -nocerts -nodes -out key.pem

# 分离CA证书
openssl pkcs12 -in cert.p12 -nokeys -cacerts -out ca.pem
```

### JKS转换 (需要keytool)

```bash
# PKCS12 -> JKS (使用keytool)
keytool -importkeystore \
  -srckeystore cert.p12 -srcstoretype PKCS12 \
  -destkeystore cert.jks -deststoretype JKS

# JKS -> PKCS12
keytool -importkeystore \
  -srckeystore cert.jks -srcstoretype JKS \
  -destkeystore cert.p12 -deststoretype PKCS12
```

---

## 证书链操作

### 合并证书

```bash
# 合并多个证书 (服务器证书 + 中间CA)
cat server.crt intermediate.crt > chain.pem

# 合并CA证书链
cat ca.crt intermediate.crt > ca-chain.pem
```

### 拆分证书

```bash
# 从chain中提取第一个证书
awk 'BEGIN{cert=0} /-----BEGIN CERTIFICATE-----/{cert=1} cert{print} /-----END CERTIFICATE-----/{if(cert) exit}' chain.pem > first.pem

# 使用OpenSSL分离
openssl crl2pkcs7 -nocrl -certfile chain.pem | openssl pkcs7 -print_certs -noout
```

### 查看证书链详情

```bash
# 查看证书链中的每个证书
openssl storeutl -noout -text -certs chain.pem

# 验证证书链完整性
openssl verify -CAFile root-ca.crt -untrusted intermediate.crt leaf.crt
```

---

## 常用场景命令

### 创建自签名服务器证书

```bash
# 1. 生成私钥
openssl genrsa -out server.key 2048

# 2. 生成CSR
openssl req -new -key server.key -out server.csr \
  -subj "/C=CN/L=Beijing/O=MyOrg/CN=example.com"

# 3. 自签名
openssl x509 -req -in server.csr -signkey server.key -out server.crt -days 365

# 4. 转为PKCS12
openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12
```

### 检查证书与私钥是否匹配

```bash
# 计算并比较指纹
openssl x509 -in cert.pem -noout -modulus | openssl md5
openssl rsa -in key.pem -noout -modulus | openssl md5

# 如果匹配，两个命令输出应相同
```

### 提取远程服务器证书

```bash
# 保存远程证书到本地
echo | openssl s_client -connect example.com:443 -servername example.com | \
  openssl x509 > remote.crt

# 保存完整证书链
echo | openssl s_client -connect example.com:443 -servername example.com | \
  sed -n '/-----BEGIN/,/-----END/p' > chain.pem
```

---

## OpenSSL 配置

### 配置文件位置

- Windows: `C:\Program Files\OpenSSL-Win64\openssl.cnf`
- Linux/macOS: `/etc/ssl/openssl.cnf`

### 查看当前配置

```bash
openssl version -a
openssl env
```

---

## 错误排查

### 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `unable to get local issuer certificate` | 缺少CA证书 | 添加 `-CAFile` 或 `-CApath` |
| `self signed certificate` | 自签名证书 | 使用 `-CAFile` 验证或忽略 |
| `certificate has expired` | 证书过期 | 续期或重新签发 |
| `wrong purpose` | 证书用途不匹配 | 检查证书的 extensions |
| `UNABLE_TO_VERIFY_SIGNATURE` | 签名算法不支持 | 升级OpenSSL版本 |
