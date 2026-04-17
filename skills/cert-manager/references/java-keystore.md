# Java KeyStore 与 Maven SSL 配置

## 概述

Java 使用 KeyStore 存储密钥和证书，Maven 通过 settings.xml 配置 SSL 证书信任。

---

## keytool 常用命令

### 基本操作

```bash
# 查看KeyStore内容
keytool -list -v -keystore keystore.jks

# 查看单个证书
keytool -list -v -keystore keystore.jks -alias mycert

# 查看PKCS12格式
keytool -list -v -keystore cert.p12 -storetype PKCS12
```

### 导入证书

```bash
# 导入证书到KeyStore（自动创建）
keytool -importcert \
  -alias mycert \
  -file cert.pem \
  -keystore keystore.jks

# 导入证书（指定storepass）
keytool -importcert \
  -alias mycert \
  -file cert.pem \
  -keystore keystore.jks \
  -storepass changeit

# 导入根CA证书
keytool -importcert \
  -alias rootca \
  -file root-ca.crt \
  -keystore truststore.jks \
  -trustcacerts
```

### 生成自签名证书

```bash
# 生成KeyPair
keytool -genkeypair \
  -alias myserver \
  -keyalg RSA \
  -keysize 2048 \
  -validity 365 \
  -keystore keystore.jks \
  -storepass changeit \
  -keypass changeit \
  -dname "CN=localhost, OU=Dev, O=MyOrg, C=CN"

# 生成CSR
keytool -certreq \
  -alias myserver \
  -keystore keystore.jks \
  -file.csr

# 导入签名后的证书
keytool -importcert \
  -alias myserver \
  -file server.crt \
  -keystore keystore.jks
```

### 删除证书

```bash
keytool -delete \
  -alias mycert \
  -keystore keystore.jks
```

### 更改密码

```bash
keytool -storepasswd \
  -keystore keystore.jks
```

---

## JKS / PKCS12 转换

### PKCS12 → JKS

```bash
# 非交互式转换（推荐），必须指定-srcstorepass
keytool -importkeystore \
  -srckeystore cert.p12 \
  -srcstoretype PKCS12 \
  -srcstorepass "" \
  -destkeystore keystore.jks \
  -deststoretype JKS \
  -deststorepass changeit \
  -noprompt
```

> ⚠️ 如果 PKCS12 文件使用空密码，必须使用 `-srcstorepass ""` 参数，否则 keytool 会尝试交互式读取密码导致失败。

### JKS → PKCS12

```bash
keytool -importkeystore \
  -srckeystore keystore.jks \
  -srcstoretype JKS \
  -destkeystore cert.p12 \
  -deststoretype PKCS12
```

### OpenSSL 方式 (推荐)

```bash
# PKCS12 -> PEM (使用OpenSSL)
openssl pkcs12 -in cert.p12 -nodes -out cert.pem

# 从PEM提取私钥和证书
# 私钥: cert.key
# 证书: cert.crt
# CA: ca.pem
```

---

## Maven settings.xml 配置

### 基本配置结构

```xml
<settings>
  <profiles>
    <profile>
      <id>my-https-settings</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <properties>
        <!-- 自定义TrustStore -->
        <javax.net.ssl.trustStore>${user.home}/.m2/truststore.jks</javax.net.ssl.trustStore>
        <javax.net.ssl.trustStorePassword>changeit</javax.net.ssl.trustStorePassword>
        <javax.net.ssl.keyStore>${user.home}/.m2/keystore.p12</javax.net.ssl.keyStore>
        <javax.net.ssl.keyStorePassword>changeit</javax.net.ssl.keyStorePassword>
        <javax.net.ssl.keyStoreType>PKCS12</javax.net.ssl.keyStoreType>
      </properties>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>my-https-settings</activeProfile>
  </activeProfiles>
</settings>
```

### Maven 命令行覆盖

```bash
# 使用自定义TrustStore
mvn -Djavax.net.ssl.trustStore=/path/to/truststore.jks \
    -Djavax.net.ssl.trustStorePassword=changeit \
    verify

# 禁用SSL验证（仅测试用！）
mvn -DskipTests -Dmaven.test.skip=true \
    -Djavax.net.ssl.trustStore=/dev/null \
    verify
```

### 完整示例

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                              http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <profiles>
    <!-- 开发环境 -->
    <profile>
      <id>dev</id>
      <properties>
        <javax.net.ssl.trustStore>${user.home}/.m2/truststore-dev.jks</javax.net.ssl.trustStore>
        <javax.net.ssl.trustStorePassword>devpass</javax.net.ssl.trustStorePassword>
      </properties>
    </profile>

    <!-- 生产环境 -->
    <profile>
      <id>prod</id>
      <properties>
        <javax.net.ssl.trustStore>${user.home}/.m2/truststore-prod.jks</javax.net.ssl.trustStore>
        <javax.net.ssl.trustStorePassword>${env.TRUSTSTORE_PASSWORD}</javax.net.ssl.trustStorePassword>
      </properties>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>dev</activeProfile>
  </activeProfiles>
</settings>
```

---

## Java 代码 SSL 配置

### 使用自定义 TrustStore

```java
import javax.net.ssl.*;
import java.io.*;
import java.security.*;
import java.security.cert.*;

public class SSLConfig {
    public static void main(String[] args) throws Exception {
        // 加载TrustStore
        String trustStorePath = System.getProperty("javax.net.ssl.trustStore");
        String trustStorePassword = System.getProperty("javax.net.ssl.trustStorePassword");

        System.setProperty("javax.net.ssl.trustStore", trustStorePath);
        System.setProperty("javax.net.ssl.trustStorePassword", trustStorePassword);
        System.setProperty("javax.net.ssl.trustStoreType", "JKS");

        // 如果需要客户端证书
        String keyStorePath = System.getProperty("javax.net.ssl.keyStore");
        String keyStorePassword = System.getProperty("javax.net.ssl.keyStorePassword");

        if (keyStorePath != null) {
            System.setProperty("javax.net.ssl.keyStore", keyStorePath);
            System.setProperty("javax.net.ssl.keyStorePassword", keyStorePassword);
            System.setProperty("javax.net.ssl.keyStoreType", "PKCS12");
        }

        // 验证配置
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(null, null, new SecureRandom());
        System.out.println("SSL配置已加载");
    }
}
```

### 使用代码配置 TrustManager（不修改系统属性）

```java
import javax.net.ssl.*;
import java.io.*;
import java.security.*;
import java.security.cert.*;

public class CustomTrustManager {
    public static void main(String[] args) throws Exception {
        // 创建TrustStore
        KeyStore trustStore = KeyStore.getInstance("JKS");
        try (FileInputStream fis = new FileInputStream("truststore.jks")) {
            trustStore.load(fis, "changeit".toCharArray());
        }

        // 创建TrustManagerFactory
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(
            TrustManagerFactory.getDefaultAlgorithm()
        );
        tmf.init(trustStore);

        // 创建SSLContext
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, tmf.getTrustManagers(), null);

        // 使用SSLContext创建HttpsURLConnection
        URL url = new URL("https://example.com/api");
        HttpsURLConnection conn = (HttpsURLConnection) url.openConnection();
        conn.setSSLSocketFactory(sslContext.getSocketFactory());

        // 读取响应
        int responseCode = conn.getResponseCode();
        System.out.println("Response Code: " + responseCode);
    }
}
```

### 绕过 SSL 验证（仅用于测试！）

```java
import javax.net.ssl.*;
import java.security.*;
import java.security.cert.*;

// ⚠️ 仅用于测试环境！
public class TestSSLUtil {
    public static void disableSSLVerification() throws NoSuchAlgorithmException {
        // 创建不验证证书的TrustManager
        TrustManager[] trustAllCerts = new TrustManager[]{
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return null; }
                public void checkClientTrusted(X509Certificate[] certs, String authType) {}
                public void checkServerTrusted(X509Certificate[] certs, String authType) {}
            }
        };

        try {
            SSLContext sc = SSLContext.getInstance("SSL");
            sc.init(null, trustAllCerts, new SecureRandom());
            HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory());

            // 同时忽略主机名验证
            HttpsURLConnection.setDefaultHostnameVerifier((hostname, session) -> true);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

---

## Spring Boot SSL 配置

### application.yml

```yaml
server:
  port: 8443
  ssl:
    enabled: true
    # 密钥库配置
    key-store: classpath:keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12
    key-alias: mycert
    # 信任库配置（双向认证）
    trust-store: classpath:truststore.jks
    trust-store-password: changeit
    trust-store-type: JKS
    client-auth: need  # need=双向认证, want=可选, none=单向
```

### application.properties

```properties
# 单向认证
server.port=8443
server.ssl.enabled=true
server.ssl.key-store=classpath:keystore.p12
server.ssl.key-store-password=changeit
server.ssl.key-store-type=PKCS12
server.ssl.key-alias=mycert

# 双向认证 (mTLS)
server.ssl.client-auth=need
server.ssl.trust-store=classpath:truststore.jks
server.ssl.trust-store-password=changeit
```

---

## 常见问题排查

### 1. PKCS12导入报错

```bash
# 错误: "keytool错误: java.io.IOException: keystore password was incorrect"

# 使用OpenSSL重新导出确保密码正确
openssl pkcs12 -in original.p12 -nodes -out temp.pem
openssl pkcs12 -export -in temp.pem -out new.p12
```

### 2. 证书链不完整

```bash
# 查看证书链
openssl s_client -connect server:443 -showcerts

# 导出完整证书链
openssl s_client -connect server:443 </dev/null | \
  sed -n '/-----BEGIN/,/-----END/p' > chain.pem

# 导入完整链到KeyStore
keytool -importcert -trustcacerts -alias intermediate \
  -file intermediate.crt -keystore truststore.jks
```

### 3. Maven 构建 SSL 错误

```bash
# 常见错误: "PKIX path building failed"

# 解决方案1: 导入证书到Java默认TrustStore
keytool -importcert \
  -alias mycert \
  -file cert.pem \
  -keystore $JAVA_HOME/lib/security/cacerts \
  -storepass changeit

# 解决方案2: 使用Maven参数
mvn -Djavax.net.ssl.trustStore=/path/to/truststore verify

# 调试SSL
mvn -Djavax.net.ssl.debug=ssl:trustmanager verify
```

### 4. 查看Java默认TrustStore

```bash
# Java 11+
keytool -list -cacerts -v

# 密码通常是 "changeit" 或 "changeme"
```

### 5. 调试 SSL 连接

```java
// 启用SSL调试
System.setProperty("javax.net.debug", "ssl:handshake:verbose");

// 或者
-Djavax.net.debug=ssl:handshake
```

---

## 工具脚本

### 准备 Java SSL 环境的完整脚本

```bash
#!/bin/bash
# setup-java-ssl.sh

CA_CERT="root-ca.crt"
KEYSTORE_PASS="changeit"
SRC_PKCS12_PASS=""  # PKCS12源密码（通常为空）

# 1. 创建TrustStore并导入CA
keytool -importcert \
  -alias rootca \
  -file "$CA_CERT" \
  -keystore truststore.jks \
  -storepass "$KEYSTORE_PASS" \
  -trustcacerts \
  -noprompt

# 2. 将PKCS12转换为JKS（非交互式，必须指定-srcstorepass）
keytool -importkeystore \
  -srckeystore server.p12 \
  -srcstoretype PKCS12 \
  -srcstorepass "$SRC_PKCS12_PASS" \
  -destkeystore server.keystore.jks \
  -deststoretype JKS \
  -deststorepass "$KEYSTORE_PASS" \
  -noprompt

# 3. 导入中间CA到KeyStore（完整证书链）
keytool -importcert \
  -alias intermediateca \
  -file intermediate-ca.crt \
  -keystore server.keystore.jks \
  -storepass "$KEYSTORE_PASS" \
  -trustcacerts \
  -noprompt

# 4. 验证TrustStore
keytool -list -keystore truststore.jks -storepass "$KEYSTORE_PASS"

# 5. 使用示例
echo "TrustStore创建完成。使用以下参数："
echo "  -Djavax.net.ssl.trustStore=$(pwd)/truststore.jks"
echo "  -Djavax.net.ssl.trustStorePassword=$KEYSTORE_PASS"
```
