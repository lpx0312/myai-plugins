---
name: claude-plugin-creator
description: 创建和发布 Claude Code 插件到插件市场。当用户想创建插件、配置 marketplace.json、发布 MCP 服务器插件、或了解插件格式时使用。必须使用此技能处理任何 Claude Code 插件开发任务。
---

# Claude Code 插件市场制作指南

## 概述

Claude Code 插件可以包含 Skills（技能）和 MCP Servers（MCP 服务器）。本指南帮助你创建、配置和发布插件到插件市场。

## 插件目录结构

### 基本结构

```
my-plugins/
├── .claude-plugin/
│   └── marketplace.json      # 插件市场定义
├── skills/                   # Skills 插件目录
│   ├── skill-a/
│   │   └── SKILL.md
│   └── skill-b/
│       └── SKILL.md
└── plugins/                  # MCP 插件目录
    └── mcp-server/
        ├── .claude-plugin/
        │   └── plugin.json
        └── config.json
```

## 两种插件格式

### 1. Skills 插件

Skills 插件用于定义 Claude 的行为和能力。

**marketplace.json 配置：**

```json
{
  "name": "my-skills",
  "description": "我的技能集合",
  "source": "./",
  "strict": false,
  "skills": [
    "./skills/skill-a",
    "./skills/skill-b"
  ]
}
```

**SKILL.md 格式：**

```markdown
---
name: skill-name
description: 技能描述，说明何时触发
---

# 技能标题

技能内容...
```

### 2. MCP 插件

MCP 插件用于集成外部工具和服务。

**plugin.json 配置（重要：mcpServers 必须在这里定义）：**

```json
{
  "name": "my-mcp-server",
  "description": "我的 MCP 服务器",
  "author": {
    "name": "Your Name"
  },
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "package-name",
        "--config-file",
        "${CONFIG_PATH}"
      ]
    }
  }
}
```

**marketplace.json 配置：**

```json
{
  "name": "my-mcp-server",
  "description": "MCP 服务器描述",
  "source": "./plugins/my-mcp-server",
  "category": "mcp"
}
```

## 完整示例

### 示例 1：创建 Skills 插件

假设你有两个技能想打包：

```
my-plugins/
├── .claude-plugin/
│   └── marketplace.json
└── skills/
    ├── code-reviewer/
    │   └── SKILL.md
    └── test-generator/
        └── SKILL.md
```

**marketplace.json：**

```json
{
  "name": "dev-tools",
  "description": "开发工具集",
  "owner": {
    "name": "Your Name",
    "email": "your@email.com"
  },
  "plugins": [
    {
      "name": "code-review-skills",
      "description": "代码审查技能集",
      "source": "./",
      "strict": false,
      "skills": [
        "./skills/code-reviewer",
        "./skills/test-generator"
      ]
    }
  ]
}
```

### 示例 2：创建 MCP 插件

```
my-plugins/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    └── ssh-server/
        ├── .claude-plugin/
        │   └── plugin.json
        └── ssh-config.json
```

**plugin.json（关键：mcpServers 必须在这里）：**

```json
{
  "name": "ssh-mcp-server",
  "description": "SSH 远程连接 MCP 服务器",
  "mcpServers": {
    "ssh-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic/ssh-mcp-server"]
    }
  }
}
```

**marketplace.json：**

```json
{
  "name": "my-plugins",
  "description": "我的插件集合",
  "plugins": [
    {
      "name": "ssh-mcp-server",
      "description": "SSH 远程连接工具",
      "source": "./plugins/ssh-server",
      "category": "mcp"
    }
  ]
}
```

## 常见错误和解决方案

### 错误 1：MCP 服务器不启动

**症状**：插件已安装（`claude plugins list` 显示），但 `claude mcp list` 不显示。

**原因**：`mcpServers` 定义在了单独的 `mcp.json` 文件里，而不是 `plugin.json`。

**解决**：将 `mcpServers` 移到 `plugin.json` 里。

### 错误 2：Skills 不触发

**症状**：安装了插件，但技能没有出现在可用列表中。

**原因**：`skills` 路径配置错误。

**解决**：检查 `marketplace.json` 中的 `skills` 路径是否正确。

### 错误 3：插件安装失败

**症状**：`claude plugins install` 报错。

**原因**：`marketplace.json` 格式错误。

**解决**：验证 JSON 格式，确保必需字段完整。

## marketplace.json 完整字段说明

```json
{
  "name": "marketplace-name",           // 市场名称
  "description": "描述",                 // 市场描述
  "owner": {
    "name": "Owner Name",               // 所有者名称
    "email": "owner@email.com"          // 所有者邮箱
  },
  "plugins": [
    {
      "name": "plugin-name",            // 插件名称（必需）
      "description": "插件描述",         // 插件描述（必需）
      "source": "./path/to/plugin",     // 插件路径（必需）
      "category": "development",        // 分类（可选）
      "strict": false,                  // 严格模式（可选）
      "skills": [                       // Skills 列表（Skills 插件必需）
        "./skills/skill-1",
        "./skills/skill-2"
      ]
    }
  ]
}
```

## 最佳实践

1. **一个仓库多个插件**：使用 `source: "./"` 和 `skills` 数组定义 Skills 插件
2. **MCP 插件独立目录**：每个 MCP 插件放在 `plugins/` 下的独立目录
3. **mcpServers 必须在 plugin.json**：不要使用单独的 `mcp.json` 文件
4. **清晰的分类**：使用 `category` 字段帮助用户筛选插件
5. **描述要详细**：`description` 字段影响插件的可发现性

## 发布流程

1. 创建 Git 仓库
2. 按照上述结构组织文件
3. 配置 `marketplace.json`
4. 推送到 GitHub
5. 用户通过 `claude plugins install <repo-url>` 安装

## 验证清单

- [ ] marketplace.json 格式正确
- [ ] plugin.json 包含 mcpServers（如果是 MCP 插件）
- [ ] skills 路径指向正确的目录
- [ ] SKILL.md 包含正确的 frontmatter
- [ ] 所有必需文件都已提交
