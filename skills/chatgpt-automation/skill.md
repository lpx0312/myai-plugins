---
name: chatgpt-automation
description: >
  Automate ChatGPT in 2 tool calls. Use when user wants to ask ChatGPT a question.
  Prerequisites: Chrome with remote debugging enabled, already logged into ChatGPT.
---

# ChatGPT Automation (Optimized)

## Prerequisites

1. Chrome browser with remote debugging enabled (port 9222)
2. Already logged into ChatGPT (https://chatgpt.com/)
3. chrome-devtools MCP running

## Workflow (2 Steps Only)

### Step 1: Navigate to ChatGPT

Direct tool call (no ToolSearch needed):

```
mcp__chrome-devtools__navigate_page(type="url", url="https://chatgpt.com/")
```

### Step 2: Execute Script to Ask Question

Replace `${question}` with the actual question, then call:

```javascript
mcp__chrome-devtools__evaluate_script(function=`() => {
  return new Promise((resolve) => {
    const q = "${question}";

    // 1. Find and fill textarea
    const ta = document.querySelector('textarea');
    if (!ta) return resolve({ success: false, error: "找不到输入框" });

    // Use native setter to trigger React events
    Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')
      .set.call(ta, q);
    ta.dispatchEvent(new Event('input', { bubbles: true }));

    // 2. Click send button after brief delay
    setTimeout(() => {
      const btn = [...document.querySelectorAll('button')]
        .find(b => (b.getAttribute('aria-label') || '').includes('发送') && !b.disabled);
      if (!btn) return resolve({ success: false, error: "发送按钮不可用" });
      btn.click();

      // 3. Wait for response completion (poll for Stop button disappearing)
      const check = setInterval(() => {
        if (!document.querySelector('button[aria-label*="Stop"]')) {
          clearInterval(check);
          const articles = document.querySelectorAll('article');
          const last = articles[articles.length - 1];
          resolve({
            success: true,
            answer: {
              text: last?.textContent,
              html: last?.querySelector('.markdown')?.innerHTML
            }
          });
        }
      }, 500);

      // Timeout after 2 minutes
      setTimeout(() => {
        clearInterval(check);
        resolve({ success: false, error: "等待响应超时" });
      }, 120000);
    }, 100);
  });
}`)
```

### Step 3: Parse Result

The script returns:
```javascript
{
  success: true/false,
  error: "错误信息（如果失败）",
  answer: {
    text: "纯文本答案",
    html: "HTML格式答案（保留代码块、列表等格式）"
  }
}
```

## Error Handling

| Error | Solution |
|-------|----------|
| 找不到输入框 | 页面可能未加载完成，重试导航 |
| 发送按钮不可用 | 检查是否已登录 ChatGPT |
| 等待响应超时 | ChatGPT 响应慢，可延长超时时间 |

## Tools Used (Fixed Names)

- `mcp__chrome-devtools__navigate_page`
- `mcp__chrome-devtools__evaluate_script`

## Performance Comparison

| Metric | Before | After |
|--------|--------|-------|
| Tool calls | 6-10 | 2 |
| ToolSearch calls | 3-4 | 0 |
| take_snapshot calls | 3-5 | 0 |

## Notes

1. **Question escaping**: If the question contains quotes or backticks, escape them properly before injecting into the script
2. **Long responses**: The 2-minute timeout should be sufficient for most responses, adjust if needed
3. **Format preservation**: Use `answer.html` for markdown-formatted output with code blocks, lists, etc.
