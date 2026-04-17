---
name: obsidian-organizer
description: Use when organizing notes, extracting tags, migrating old 

#tag format, optimizing metadata, or establishing note links. Coordinates with official obsidian-skills for vault operations and formatting.
---

# Obsidian 笔记智能组织器

智能整理 Obsidian 笔记库，协调官方 skills 完成标签提取、元数据优化、旧格式迁移、笔记关联建立。

**核心价值**：标签提取策略 + 元数据规范 + Wikilink 验证规则 + 协作编排

---

## 技能协作架构

```
obsidian-organizer (协调层)
├── obsidian-cli (官方)      → Vault 操作（搜索、读取、设置属性）
├── obsidian-markdown (官方) → 正文格式（wikilink、callout、表格）
├── defuddle (官方)          → 网页内容提取
├── json-canvas (官方)       → 关系图谱
└── obsidian-bases (官方)    → 索引视图
```

**REQUIRED SUB-SKILLS:**
- **格式规范**: 使用 obsidian-markdown 的 wikilinks、callouts、代码块规范
- **Vault 操作**: 使用 obsidian-cli 的 search、read、property:set 命令
- **网页提取**: 使用 defuddle 提取网页内容为 Markdown
- **Canvas 图谱**: 使用 json-canvas 创建笔记关系可视化
- **索引视图**: 使用 obsidian-bases 创建笔记库数据库视图

---

## 核心工作流程

### 1. 智能整理现有笔记

```
obsidian-cli search → 分析内容 → 提取标签 → 设置元数据 → 优化格式
```

**步骤：**

1. **搜索笔记** → `obsidian-cli search` 定位目标笔记
2. **读取内容** → `obsidian-cli read` 获取完整内容
3. **分析提取** → 从文件名、标题、代码块、旧格式标签中手动提取关键词
4. **设置元数据** → `obsidian-cli property:set` 设置 tags、category
5. **优化格式** → **引用 obsidian-markdown** 规范化正文
6. **建立关联** → 添加 WikiLink 和外部链接
7. **Wikilink 验证** → 必须验证所有链接目标存在（见下方验证规则）
8. **图片处理** → 仅在需要时下载本地化

---

## 标签提取规则

**核心能力**：从文件名、标题、代码块、旧格式标签 中智能提取。

| 提取源 | 方法 | 示例 |
|--------|------|------|
| 文件名 | 拆分关键词 | `ens33更改为eth0-进入再改.md` → `ens33转eth0` |
| 标题 | 关键词识别 | `CentOS7` → `CentOS`, `Linux` |
| 旧格式 `#标签` | 正则提取 | `#nacos安装` → `nacos安装` |
| 代码块 | 命令解析 | `grub2-mkconfig` → `GRUB配置` |
| 目录路径 | 推断分类 | `SRE/Linux基础/` → `SRE/Linux` |

**提取优先级**：旧格式标签 > 文件名 > 标题 > 代码块 > 目录

---

## 旧格式标签迁移

识别并迁移正文中的 `#标签` 到 frontmatter：

```markdown
# 迁移前
#nacos安装
#nacos单节点安装

# 笔记内容...

---
# 迁移后
---
tags:
  - nacos安装
  - nacos单节点安装
---

# 笔记内容...
```

**识别规则**：
- ✅ 识别：`#标签名`（独立行，#后无空格）
- ❌ 不识别：`# 标题`（标题格式）、`# 注释`（代码块内）

---

## 元数据规范

### 必需字段

```yaml
---
tags:           # 3-7 个标签，直接可搜索
  - Linux
  - CentOS
  - 网卡配置
category: SRE/Linux/网络配置  # 主分类
---
```

### 可选字段

| 字段 | 示例 |
|------|------|
| created | `2026-01-23` |
| updated | `2026-01-23T22:26` |
| status | `✅ 已验证` / `🚧 草稿` |
| difficulty | `初级/中级/高级` |
| importance | `低/中/高` |
| sources | `["https://..."]` (纯URL) |

### 标签体系

```
技术栈 (K8S, Docker, Linux)
  ↓
组件/模块 (K8S/Pod, Docker/镜像)
  ↓
场景 (安装配置, 故障排查, 命令参考)
  ↓
具体问题 (ens33转eth0, Pod重启)
```

**原则**：
- ✅ 标签名 = 搜索词
- ✅ 技术术语用英文
- ❌ 标签中不用 emoji

详细标签树见 [references/tag_taxonomy.md](references/tag_taxonomy.md)

---

## Wikilink 验证规则（强制执行）

**❌ 常见错误：添加了指向不存在笔记的 Wikilink**

```yaml
# 错误示例：目标笔记不存在，链接会变成红色无法点击
related:
  - [[kubectl常用命令清单]]      # ❌ 不存在！
  - [[kubectl proxy用法]]         # ❌ 不存在！
```

**✅ 正确流程：添加 Wikilink 前必须验证目标笔记存在**

```
建立关联步骤：
1. 搜索 vault 中是否存在目标笔记（使用 obsidian-cli search）
2. 确认笔记名称完全匹配（包括空格和标点）
3. 添加 wikilink 时使用确认后的准确笔记名
4. 验证链接可以正常点击
```

**验证方法：**

```bash
# 1. 搜索目标笔记是否存在于 vault 中
obsidian search query="笔记关键词" limit=10

# 2. 确认文件实际名称（Obsidian 使用文件名作为链接目标）
# 注意：文件 "03 - kubectl proxy.md" 的链接目标是 [[03 - kubectl proxy]]，不是 [[kubectl proxy]]！

# 3. 如果笔记不存在，有两种处理方式：
#    a) 不添加链接（推荐），等笔记创建后再关联
#    b) 先创建空笔记，再建立关联
```

> [!WARNING] **`related` 字段禁止使用 Wikilink（强制规则）**
>
> ❌ **禁止**在 `related` 字段中使用 `[[笔记名]]` 格式
>
> ✅ **正确做法** - 在正文末尾添加相关链接：
> ```markdown
> ## 相关笔记
>
> - [[000-k8S命令清单]]
> - [[03 - kubectl port-forward与proxy]]
> ```

---

## 协作技能用法

### obsidian-cli — Vault 操作

**使用官方 obsidian-cli skill**，常用命令：

```bash
# 搜索笔记
obsidian search query="Docker" limit=10

# 读取笔记内容
obsidian read file="笔记名称"

# 设置元数据（需要 Obsidian 运行）
obsidian property:set name="tags" value="Docker,故障排查" file="笔记名称"
obsidian property:set name="category" value="容器技术" file="笔记名称"

# 列出所有标签
obsidian tags sort=count counts
```

### obsidian-markdown — 正文格式

**引用官方 obsidian-markdown skill**，包括：
- **Wikilinks**：`[[笔记名]]` 关联笔记
- **Callouts**：`> [!note]` 高亮信息
- **表格**：列表转表格提升可读性
- **代码块**：指定语言 ` ```bash `
- **属性**：frontmatter 规范

详细规范见官方 obsidian-markdown skill。

### defuddle — 网页内容导入

```bash
# 提取网页内容为 Markdown
defuddle parse <url> --md -o content.md

# 获取标题
defuddle parse <url> -p title
```

### json-canvas — 关系图谱

创建笔记关联的可视化画布：
- 节点 = 笔记
- 边 = 关联关系
- 用于梳理知识体系

### obsidian-bases — 索引视图

创建笔记库的数据库视图：
- 按标签/分类筛选
- 多维度排序
- 统计汇总

---

## 图片处理规范

**原则：保持稳定外链优先，仅在必要时本地化。**

| 场景 | 处理方式 |
|:-----|:---------|
| 稳定图床（自己的 CDN、GitHub、Imgur 等） | **保留外链**，不改路径 |
| 临时/匿名 URL（如 `i.imgur.io/xxx?t=xxx`） | 下载本地化 |
| 404 或无法访问的外链 | 下载或删除 |
| 用户明确要求本地化 | 下载本地化 |
| 图片命名已表达含义（如 `01-Yum仓库架构图.png`） | **保留外链** |

### 本地化方法

当需要下载图片时，优先保留原文件名：

```bash
# 下载到笔记同目录，保持原文件名
curl -sfo "原文件名.png" "https://example.com/path/image.png"
```

嵌入语法：`![[原文件名.png]]`

---

## 执行检查清单

整理笔记时：

- [ ] 1. 使用 `obsidian-cli search` 定位笔记
- [ ] 2. 使用 `obsidian-cli read` 读取内容
- [ ] 3. 分析文件名、标题、代码块提取关键词
- [ ] 4. 识别并迁移旧格式 `#标签` 到 frontmatter
- [ ] 5. 使用 `obsidian-cli property:set` 设置 tags、category
- [ ] 6. 优化正文格式（**引用 obsidian-markdown**）
- [ ] **6.1 为 H2 章节标题添加 emoji 前缀**（如 `## 🧩 一、概念`、`## 🔧 二、方法`）
- [ ] **6.2 H1 标题可加状态 emoji**（如 `# ✅ 已验证笔记名`）
- [ ] 7. 建立笔记关联（wikilinks）
- [ ] **7.1 ⚠️ 禁止在 `related` 字段使用 wikilink！链接必须放在正文末尾的 `## 相关笔记` section**
- [ ] **7.2 使用 `obsidian-cli search` 验证每个 wikilink 目标笔记存在**
- [ ] **7.3 确认 wikilink 名称与实际文件名完全匹配**
- [ ] 8. 添加参考资源（外部链接）
- [ ] 9. 图片处理：稳定外链保留，仅在需要时本地化

---

## 参考文档

详细规范见：
- [标签分类体系](references/tag_taxonomy.md)
- [格式规范](references/formatting_guide.md)
- [常见问题](references/faq.md)
