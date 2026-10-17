---
name: zlibrary-downloader
description: Z-Library电子书下载助手。使用chrome-devtools MCP在Z-Library(https://zh.zlib.li/)上搜索和下载电子书。支持中文和英文书籍搜索，自动处理搜索、获取书籍详情、下载文件等流程。使用场景：(1) 用户需要在Z-Library上下载电子书 (2) 用户已登录或需要登录Z-Library账号 (3) 用户提供书名进行搜索下载
---

# Z-Library 电子书下载助手

本指南使用chrome-devtools MCP在Z-Library上搜索和下载电子书。

## 前置准备

### 打开Z-Library网站

使用chrome-devtools打开网站：

```
打开: https://zh.zlib.li/
```

### 等待用户登录

**重要**: Z-Library需要登录才能下载书籍。

1. 检查页面是否有登录按钮
2. 提示用户手动登录
3. 等待用户确认登录完成

检查登录状态的JavaScript：

```javascript
// 检查是否已登录（有用户头像或"我的图书馆"可访问）
() => {
  const userIcon = document.querySelector('[data-test-id="header-user-icon"], .user-icon');
  const myLibraryLink = document.querySelector('a[href*="/profile"]');
  return {
    hasUserIcon: !!userIcon,
    hasMyLibrary: !!myLibraryLink,
    isLoggedIn: !!userIcon || !!myLibraryLink
  };
}
```

## 搜索书籍

### 执行搜索

在搜索框中输入书名并搜索：

```javascript
// 方法1: 直接导航到搜索结果页面
// 将书名进行URL编码
导航到: https://zh.zlib.li/s/[URL编码的书名]

// 示例：搜索"简爱"
// https://zh.zlib.li/s/%E7%AE%80%E7%88%B1
```

或使用表单填写方式：

```javascript
// 方法2: 填写搜索框
1. 找到搜索框: input[placeholder*="搜索"]
2. 输入书名
3. 点击搜索按钮
```

### 获取搜索结果

从搜索结果页面提取书籍信息：

```javascript
// 获取第一本书的ID和下载链接
() => {
  const bookItem = document.querySelector('.book-item, [data-check-id], article');
  if (!bookItem) return { error: '未找到书籍' };

  const bookCard = bookItem.querySelector('z-bookcard');
  if (!bookCard) return { error: '未找到书籍卡片' };

  return {
    bookId: bookCard.getAttribute('id'),
    href: bookCard.getAttribute('href'),
    download: bookCard.getAttribute('download')
  };
}
```

返回示例：
```json
{
  "bookId": "5723654",
  "href": "/book/5723654/467d3f/%E7%AE%80%E7%88%B1.html",
  "download": "/dl/5723654/383a54"
}
```

## 进入书籍详情页

使用获取的信息导航到书籍详情页：

```
导航到: https://zh.zlib.li[href值]
```

示例：
```
https://zh.zlib.li/book/5723654/467d3f/%E7%AE%80%E7%88%B1.html
```

## 下载书籍

### 方法1: 直接点击下载链接

```javascript
// 查找并点击下载链接
() => {
  const downloadLinks = Array.from(document.querySelectorAll('a')).filter(a =>
    a.href.includes('/dl/')
  );

  if (downloadLinks.length > 0) {
    downloadLinks[0].click();
    return { clicked: true, href: downloadLinks[0].href };
  }
  return { clicked: false };
}
```

### 方法2: 使用完整下载URL

如果获取了download路径，可以直接导航：

```
导航到: https://zh.zlib.li[download值]
```

示例：
```
https://zh.zlib.li/dl/5723654/383a54
```

**注意**: 直接导航到下载链接可能会被浏览器阻止（ERR_ABORTED）。建议使用方法1（点击链接）。

## 验证下载成功

下载成功后，书籍详情页会显示"Downloaded"状态标记。

```javascript
// 检查下载状态
() => {
  const downloadedBadge = document.querySelector('[data-test-id*="downloaded"], .downloaded-badge');
  const statusText = document.body.textContent.includes('已下载') || document.body.textContent.includes('Downloaded');
  return {
    hasBadge: !!downloadedBadge,
    hasStatusText: statusText
  };
}
```

## 完整工作流程

### 单本书籍下载流程

1. **打开网站** → 导航到 https://zh.zlib.li/
2. **检查登录** → 等待用户手动登录
3. **搜索书籍** → 导航到 `/s/[书名]`
4. **获取书籍ID** → 从搜索结果提取 `bookId` 和 `href`
5. **进入详情页** → 导航到书籍详情页
6. **点击下载** → 使用JavaScript点击下载链接
7. **确认完成** → 检查"Downloaded"标记

### 批量下载多本书籍

对于多本书籍，重复步骤3-7：

```
对于每本书名:
  1. 搜索书籍
  2. 获取第一项结果的bookId
  3. 导航到详情页
  4. 点击下载
  5. 返回主页继续下一本
```

## 常用chrome-devtools命令

### 导航到URL
```
mcp__chrome-devtools__navigate_page
  type: "url"
  url: "https://zh.zlib.li/..."
```

### 执行JavaScript
```
mcp__chrome-devtools__evaluate_script
  function: "() => { ... }"
```

### 获取页面快照
```
mcp__chrome-devtools__take_snapshot
```

### 截图
```
mcp__chrome-devtools__take_screenshot
```

### 点击元素
```
mcp__chrome-devtools__click
  uid: "元素UID"
```

## 常见问题处理

### 未登录状态

如果下载失败或显示错误，检查：

```javascript
// 检查是否被重定向到登录页
() => {
  const isLoginPage = window.location.href.includes('/login');
  const hasLoginForm = document.querySelector('form[action*="login"]');
  return { isLoginPage, hasLoginForm };
}
```

如果返回 `isLoginPage: true`，提示用户登录。

### 搜索无结果

如果搜索结果为空：

1. 确认书名拼写正确
2. 尝试使用简体/繁体中文
3. 尝试使用英文原名
4. 检查网络连接

### 下载失败

如果点击下载链接后出现错误：

1. 检查是否已登录
2. 刷新页面重试
3. 尝试其他格式（如果有多个格式选项）
4. 检查浏览器下载设置

## URL编码参考

中文书名需要进行URL编码：

| 书名 | URL编码 |
|------|---------|
| 简爱 | %E7%AE%80%E7%88%B1 |
| 飘 | %E9%A3%98 |
| 心的重建 | %E5%BF%83%E7%9A%84%E9%87%8D%E5%BB%BA |
| 假如给我三天光明 | %E5%81%87%E5%A6%82%E7%BB%99%E6%88%91%E4%B8%89%E5%A4%A9%E5%85%89%E6%98%8E |

可以使用JavaScript的 `encodeURIComponent()` 函数进行编码。
