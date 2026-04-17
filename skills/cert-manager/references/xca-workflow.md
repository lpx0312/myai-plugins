# XCA 使用指南

## 概述

XCA (X Certificate and Key management) 是一个开源的GUI工具，用于管理数字证书。

**主要功能：**
- 创建和管理CA（证书颁发机构）
- 生成服务器证书和客户端证书
- 证书签名请求 (CSR) 管理
- 私钥和证书的导入/导出
- 证书模板管理

**下载地址：** https://hohnstaedt.de/xca/

---

## XCA 安装

### Windows

1. 从 https://hohnstaedt.de/xca/download/xca-2.4.0-windows.zip 下载
2. 解压到 `C:\Program Files\XCA`
3. 双击 `xca.exe` 运行

### Linux (Ubuntu/Debian)

```bash
sudo apt install xca
```

### macOS

```bash
brew install --cask xca
```

---

## 创建根CA

### 步骤1：创建新的数据库

首次运行时会提示创建数据库文件（用于存储密钥和证书）：

1. 点击 "File" → "New Database"
2. 选择保存位置，如 `xca ca.db`
3. 设置数据库密码（妥善保管！）
4. 点击 "OK"

### 步骤2：创建根CA证书

1. 点击 "PKI" 标签页
2. 点击 "New Certificate" 按钮
3. 在 "Certificate" 选项卡中：
   - 点击 "Subject" 选项卡
   - 填写根CA信息：
     ```
     Common Name (CN): My Root CA
     Country (C): CN
     State (ST): Beijing
     Locality (L): Beijing
     Organization (O): My Organization
     ```
4. 点击 "Extensions" 选项卡：
   - Type: "Certificate Authority"
   - Path length: 0（表示不再允许下级CA）
5. 点击 "Key Usage" 选项卡：
   - 勾选 "Certificate Sign" 和 "CRL Sign"
6. 点击 "OK" 创建

### 步骤3：生成CA私钥

创建证书时会自动提示生成私钥：

1. 在弹出的 "Create key" 对话框中：
   - Key length: 4096（推荐）
   - Algorithm: RSA（兼容性更好）或 EC（更安全）
2. 点击 "Create"
3. 选择加密算法（如 AES256）
4. 输入私钥密码
5. 完成根CA创建

---

## 创建中间CA

当需要多级证书链时（如根CA签发中间CA，中间CA再签发服务器/客户端证书），按以下步骤创建中间CA。

### 前提条件

- 已创建根CA（见上一节）

### 步骤1：创建中间CA证书

1. 点击 "PKI" 标签页
2. 点击 "New Certificate"
3. 在 "Source" 选项卡中：
   - 选择 "Use this Certificate for signing"
   - 选择刚创建的根CA（如 "My Root CA"）
4. 点击 "Subject" 选项卡：
   ```
   Common Name (CN): My Intermediate CA
   Country (C): CN
   State (ST): Beijing
   Locality (L): Beijing
   Organization (O): My Organization
   Organizational Unit (OU): My Intermediate CA
   ```
5. 点击 "Extensions" 选项卡：
   - Type: "Certificate Authority"
   - Path length: 0（如果不允许此CA再签发下级CA）
     或留空（如果此中间CA还可以签发更多中间CA）
6. 点击 "Key Usage" 选项卡：
   - 勾选 "Certificate Sign"
   - 勾选 "CRL Sign"
   - 如果需要签发OCSP响应，勾选 "OCSP Signing"（可选）
7. 点击 "OK" 创建

### 步骤2：验证中间CA

创建完成后，验证中间CA可以签发证书：

1. 在证书列表中选中中间CA
2. 右键 "Show Details" 查看证书信息
3. 确认：
   - Issuer: 应显示根CA
   - Subject: 应显示中间CA信息
   - Basic Constraints: CA:TRUE

### 步骤3：导出中间CA证书和私钥

**导出证书（含私钥，用于签发证书）：**

1. 选中中间CA证书
2. 右键 "Export"
3. 选择 "PEM" 格式
4. 保存为 `intermediate-ca.pfx` 或 `intermediate-ca.pem`

**导出证书（仅公钥，用于部署）：**

1. 选中中间CA证书
2. 右键 "Export"
3. 选择 "PEM" 格式（不含私钥）
4. 保存为 `intermediate-ca.crt`

---

## 创建服务器证书

### 步骤1：创建证书模板（可选）

1. 点击 "Templates" 标签页
2. 点击 "New Template"
3. 填写模板信息：
   - Name: "Server Certificate"
   - Type: "Server Certificate"
4. 在 "Extensions" 中设置：
   - Type: "End Entity"
   - 勾选 "Server Authentication"
5. 点击 "OK"

### 步骤2：生成服务器证书

1. 点击 "PKI" 标签页
2. 点击 "New Certificate"
3. 在 "Certificate" 选项卡中：
   - 点击 "Source" 选项卡
   - 选择 "Use this Certificate for signing"
   - 选择签发CA（根CA 或 中间CA，根据层级选择）
4. 点击 "Subject" 选项卡：
   ```
   Common Name (CN): server.example.com
   Country (C): CN
   State (ST): Beijing
   Locality (L): Beijing
   Organization (O): My Organization
   ```
5. 点击 "Extensions" 选项卡：
   - Type: "Server Certificate" 或选择模板
   - 勾选 "Server Authentication"
   - 如果需要SAN，展开 "Subject Alternate Names" 添加：
     - DNS: `server.example.com`
     - DNS: `*.example.com`
     - IP: `192.168.1.100`（服务器IP地址）
     - IP: `10.0.0.1`（内网IP）
     - IP: `127.0.0.1`（本地回环地址，如果需要localhost访问）
   - **注意**：如果使用IP访问，必须在SAN中添加IP，不能依赖CN
6. 点击 "OK" 创建证书

### 步骤3：导出服务器证书和私钥

1. 在证书列表中选中刚创建的证书
2. 右键点击 → "Export"
3. 选择格式：
   - **PEM 证书 + 私钥（推荐）：**
     - 证书: `server.crt`
     - 私钥: `server.key` (选择私钥导出)
   - **PKCS12 (用于Java/Windows)：**
     - 选择 "PKCS#12" 格式
     - 设置密码

---

## 创建客户端证书

### 步骤1：生成客户端证书

1. 点击 "New Certificate"
2. Source: 选择根CA
3. Subject: 填写用户信息：
   ```
   Common Name (CN): john.doe
   Country (C): CN
   State (ST): Beijing
   Locality (L): Beijing
   Organization (O): My Organization
   Organizational Unit (OU): Engineering
   ```
4. Extensions: Type → "Client Certificate"
5. 勾选 "Client Authentication"
6. Key Usage: 勾选 "Digital Signature" 和 "Key Encipherment"
7. 点击 "OK"

### 步骤2：导出客户端证书

#### 方式1：PKCS12（浏览器导入）

1. 选中证书 → 右键 "Export"
2. 格式选择 "PKCS#12 (.p12)"
3. 选择对应的私钥
4. 设置导出密码
5. 保存为 `john-doe.p12`

#### 方式2：分开导出（PEM）

1. 导出证书: `john-doe.crt`
2. 导出私钥: `john-doe.key`
3. 导出CA证书: `my-root-ca.crt`（浏览器需要安装根CA）

### 步骤3：安装根CA到浏览器

#### Chrome/Edge

1. 下载根CA证书 (PEM格式)
2. 设置 → 隐私和安全 → 管理证书
3. 切换到 "受信任的根证书颁发机构"
4. 导入根CA证书

#### Firefox

1. 选项 → 隐私与安全 → 证书
2. 查看证书 → 证书颁发机构
3. 导入根CA证书

---

## 证书导出格式建议

### 格式对照表

| 用途 | 推荐格式 | 文件扩展名 |
|-----|---------|-----------|
| Nginx | PEM | .crt, .key |
| Apache | PEM | .crt, .key |
| Java/Keystore | PKCS12 | .p12 |
| Windows IIS | PFX/PKCS12 | .pfx, .p12 |
| 客户端浏览器 | PKCS12 | .p12 |
| 客户端邮件 | PEM/S/MIME | .pem |

### Nginx 配置所需文件

```
/etc/nginx/ssl/
├── server.crt      # 服务器证书（PEM格式）
├── server.key      # 服务器私钥
├── ca.crt          # 根CA证书
└── client.p12      # 客户端证书（PKCS12）
```

### Java/Keystore 配置所需文件

```
/etc/java/ssl/
├── server.p12      # 服务器证书+私钥（PKCS12）
└── truststore.jks # 信任的CA证书库
```

---

## 常见任务

### 1. 证书续期

1. 在证书列表选中要续期的证书
2. 右键 "Reissue Certificate"
3. 修改有效期
4. 重新导出

### 2. 证书撤销

1. 选中证书 → "Revoke"
2. 生成 CRL：
   - 点击 "Private Keys" 或 "Certificates"
   - 选择CA证书 → "Generate CRL"
3. 导出 CRL 文件

### 3. 批量导出

1. 在列表中选中多个证书（Ctrl+点击）
2. 右键 "Export"
3. 选择导出目录
4. 选择格式

### 4. 导入现有证书

1. 点击 "Import"
2. 选择文件类型：
   - Certificate (*.crt, *.pem)
   - PKCS#12 (*.p12, *.pfx)
   - PGP Key
3. 选择文件并导入

---

## 最佳实践

### 密码管理

- 数据库密码：使用强密码，启用加密
- 私钥密码：每个私钥单独设置密码
- 定期备份数据库文件

### 证书有效期

| 证书类型 | 推荐有效期 |
|---------|-----------|
| 根CA | 10-20年 |
| 中间CA | 5-10年 |
| 服务器证书 | 1年 |
| 客户端证书 | 1年 |

### 安全建议

1. **分离环境**：测试环境和生产环境使用不同的CA
2. **限制私钥访问**：设置操作系统权限
3. **启用审计**：记录证书操作日志
4. **定期轮换**：定期更换私钥密码

---

## 故障排除

### 导入P12失败

**问题：** 导入PKCS12时提示密码错误

**解决：**
```bash
# 使用OpenSSL检查P12内容
openssl pkcs12 -in client.p12 -info -noout

# 重新导出确保密码正确
openssl pkcs12 -in original.pem -export -out client.p12
```

### 证书不受信任

**问题：** 浏览器提示证书不受信任

**解决：**
1. 确认已安装根CA到系统信任库
2. 检查根CA的 "Trusted for" 设置
3. 确认证书链完整（服务器证书 → 中间CA → 根CA）

### 私钥不匹配

**问题：** Nginx提示 "RSA server certificate CommonName mismatch"

**解决：**
1. 检查证书的CN是否与域名匹配
2. 检查SAN设置
3. 确认服务器证书和私钥是配对的：
```bash
# 比较MD5指纹
openssl x509 -in server.crt -noout -modulus | md5sum
openssl rsa -in server.key -noout -modulus | md5sum
```
