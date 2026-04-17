# MyAITools Plugin

A Claude Code plugin for AI-powered tools with SSH and local file search capabilities.

## Structure

```
myaitools/
├── .claude-plugin/
│   └── plugin.json            # Plugin metadata
├── .mcp.json                  # MCP server configuration
├── skills/                   # Skills (slash commands and context skills)
└── commands/                 # Legacy commands format
```

## MCP Servers

### SSH MCP Server

Connects to internal network hosts via SSH:

```json
{
  "mcpServers": {
    "ssh-mcp-server": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "--registry", "http://192.168.0.12/repository/npm-group/",
        "-y",
        "@lpx/ssh-mcp-server",
        "--config-file",
        "D:\\AI\\github-code\\ssh-mcp-server\\ssh-config.json"
      ]
    }
  }
}
```

## Adding Skills

Place skill directories in `skills/` with a `SKILL.md` file:

```
skills/
  my-skill/
    SKILL.md
```

## 本仓库插件市场

```
/plugin marketplace add lpx0312/myai-plugins

```



## 还有些官方插件，需要单独安装

```
/plugin marketplace add anthropics/claude-plugins-official

/plugin install claude-md-management@claude-plugins-official
/plugin install code-review@claude-plugins-official
/plugin install code-simplifier@claude-plugins-official
/plugin install commit-commands@claude-plugins-official
/plugin install feature-dev@claude-plugins-official
/plugin install frontend-design@claude-plugins-official
/plugin install hookify@claude-plugins-official
/plugin install mcp-server-dev@claude-plugins-official
/plugin install ralph-loop@claude-plugins-official
/plugin install skill-creator@claude-plugins-official
```


- 终端执行
```bash
claude -p "/plugin marketplace add anthropics/claude-plugins-official"
claude -p "/plugin install claude-md-management@claude-plugins-official"
claude -p "/plugin install code-review@claude-plugins-official"
claude -p "/plugin install code-simplifier@claude-plugins-official"
claude -p "/plugin install commit-commands@claude-plugins-official"
claude -p "/plugin install feature-dev@claude-plugins-official"
claude -p "/plugin install frontend-design@claude-plugins-official"
claude -p "/plugin install hookify@claude-plugins-official"
claude -p "/plugin install mcp-server-dev@claude-plugins-official"
claude -p "/plugin install ralph-loop@claude-plugins-official"
claude -p "/plugin install skill-creator@claude-plugins-official"
```


## 插件更新：
1. 我的理解： 插件市场中的引用的别的仓库是 url的形式的话，可以直接找到插件人后更新，
2. 如果是本地插件 比如 "source": "./plugin", 或者 "source": "./", 这样的话，找到插件个更新根本没有意义，这种的话，直接更新插件市场就行了