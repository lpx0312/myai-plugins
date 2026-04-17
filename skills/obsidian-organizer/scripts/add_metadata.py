#!/usr/bin/env python3
"""
为 Obsidian 笔记添加标准元数据

使用方法：
    python add_metadata.py <笔记目录或文件>

功能：
    - 为没有元数据的笔记添加 frontmatter
    - 自动添加 created 和 updated 时间戳
    - 根据文件名和目录推断标签和分类
    - 提取并迁移旧格式 #标签 到 frontmatter
    - 保留已有的元数据
"""

import os
import sys
from datetime import datetime
from pathlib import Path
import re


def extract_old_tags(body):
    """
    从正文提取旧格式 #标签
    识别规则：
    - 匹配单独一行的 #标签（# 后无空格）
    - 不匹配标题 # # 标题（# 后有空格）
    - 不匹配代码块中的 #
    """
    old_tags = []

    # 移除代码块
    body_without_code = re.sub(r'```[\s\S]*?```', '', body)
    body_without_code = re.sub(r'`[^`]+`', '', body_without_code)

    # 匹配独立成行的标签
    # #标签名 (后面紧跟换行，不是标题)
    pattern = r'^#([^\s#][^\n]*?)(?=\n|$)'
    matches = re.finditer(pattern, body_without_code, re.MULTILINE)

    for match in matches:
        tag = match.group(1).strip()
        if tag and len(tag) > 0:
            old_tags.append(tag)

    return list(set(old_tags))


def extract_metadata(content):
    """提取现有的元数据，返回 (frontmatter字符串, body字符串)"""
    if content.startswith('---'):
        end = content.find('---', 3)
        if end != -1:
            frontmatter = content[3:end].strip()
            body = content[end+3:].strip()
            # 确保 body 前有两个换行（frontmatter 和 body 之间）
            if not body.startswith('\n'):
                body = '\n' + body
            return frontmatter, body
    return None, content


def parse_existing_meta(frontmatter):
    """解析现有的 frontmatter，提取各字段"""
    result = {
        'created': None,
        'updated': None,
        'tags': [],
        'category': None,
        'other': []
    }

    if not frontmatter:
        return result

    lines = frontmatter.split('\n')
    current_key = None
    current_indent = 0

    for line in lines:
        # 检查是否是键值对行（不是列表项）
        if line.strip() and not line.strip().startswith('-'):
            # 匹配 key: value 格式
            key_match = re.match(r'^(\w+):\s*(.*)$', line.strip())
            if key_match:
                current_key = key_match.group(1)
                value = key_match.group(2).strip()

                if current_key == 'created':
                    result['created'] = value
                elif current_key == 'updated':
                    result['updated'] = value
                elif current_key == 'category':
                    result['category'] = value
                elif current_key == 'tags':
                    # tags 后面会处理列表项
                    pass
                else:
                    result['other'].append(line.strip())
                continue

        # 检查是否是列表项（标签）
        if line.strip().startswith('-'):
            tag_content = line.strip()[1:].strip()
            if current_key == 'tags' and tag_content:
                result['tags'].append(tag_content)

    return result


def extract_keywords_from_filename(filepath):
    """从文件名提取关键词作为候选标签"""
    filename = Path(filepath).stem

    # 常见分隔符模式
    separators = ['-', '_', '—', '–']

    # 移除常见文件名前缀模式
    prefixes_to_remove = [
        r'^\d+[\s\-_.]*',  # 数字前缀
        r'^[\u4e00-\u9fa5]+[\s\-_.]*',  # 中文数字前缀
    ]

    for prefix in prefixes_to_remove:
        filename = re.sub(prefix, '', filename)

    # 按分隔符分割
    parts = filename
    for sep in separators:
        parts = parts.replace(sep, ' ')

    # 清理并提取有意义的词
    words = []
    for part in parts.split():
        part = part.strip()
        # 过滤太短或无意义的词
        if len(part) >= 2 and part.lower() not in ['md', 'note', '笔记', '文档']:
            words.append(part)

    return words


def infer_category_from_path(filepath):
    """从文件路径推断分类"""
    path = Path(filepath)
    parts = path.parts

    # 常见分类关键词
    category_keywords = {
        'k8s': '云原生/K8S',
        'kubernetes': '云原生/K8S',
        'docker': '云原生/Docker',
        '容器': '云原生/容器',
        'linux': 'SRE/Linux',
        'sre': 'SRE',
        'devops': 'SRE/DevOps',
        'jenkins': 'CI-CD/Jenkins',
        'gitlab': 'CI-CD/GitLab',
        'mysql': '数据库/MySQL',
        'oracle': '数据库/Oracle',
        'redis': '数据库/Redis',
        'mongodb': '数据库/MongoDB',
        'nginx': '中间件/Nginx',
        'elk': '监控/ELK',
        'prometheus': '监控/Prometheus',
        'grafana': '监控/Grafana',
        'python': '编程/Python',
        'java': '编程/Java',
        'shell': '编程/Shell',
        'bash': '编程/Shell',
    }

    category = '未分类'
    path_str = str(filepath).lower()

    for keyword, cat in category_keywords.items():
        if keyword in path_str:
            category = cat
            break

    return category


def create_frontmatter(existing_meta, filepath, old_tags=None):
    """创建或更新 frontmatter"""
    now = datetime.now().strftime('%Y-%m-%d')
    old_tags = old_tags or []

    # 如果已有元数据，更新并保留
    if existing_meta:
        parsed = parse_existing_meta(existing_meta)

        # 更新 updated 时间
        parsed['updated'] = now

        # 如果没有 created，添加
        if not parsed['created']:
            parsed['created'] = now

        # 合并旧格式标签（去重）
        existing_tags = set(parsed['tags'])
        for tag in old_tags:
            if tag not in existing_tags:
                parsed['tags'].append(tag)

        # 重建 frontmatter
        lines = ['---']

        if parsed['created']:
            lines.append(f"created: {parsed['created']}")
        if parsed['updated']:
            lines.append(f"updated: {parsed['updated']}")

        if parsed['tags']:
            lines.append("tags:")
            for tag in parsed['tags']:
                lines.append(f"  - {tag}")

        if parsed['category']:
            lines.append(f"category: {parsed['category']}")

        # 添加其他保留字段
        for other in parsed['other']:
            lines.append(other)

        lines.append('---')

        return '\n'.join(lines)

    # 创建新的元数据
    file_tags = extract_keywords_from_filename(filepath)
    category = infer_category_from_path(filepath)

    # 合并旧格式标签
    all_tags = list(set(file_tags + old_tags))

    meta_lines = ['---']
    meta_lines.append(f"created: {now}")
    meta_lines.append(f"updated: {now}")

    if all_tags:
        meta_lines.append("tags:")
        for tag in all_tags[:7]:  # 限制标签数量
            meta_lines.append(f"  - {tag}")

    meta_lines.append(f"category: {category}")
    meta_lines.append('---')

    return '\n'.join(meta_lines)


def remove_old_tags_from_body(body, old_tags):
    """从正文中删除旧格式标签行"""
    if not old_tags:
        return body

    lines = body.split('\n')
    new_lines = []

    for line in lines:
        is_old_tag_line = False

        # 检查是否是旧格式标签行（独立成行，以 # 开头但不是标题）
        stripped = line.strip()
        if stripped.startswith('#') and not stripped.startswith('# '):
            # 提取标签内容
            tag_match = re.match(r'^#([^\s#][^\n]*?)(?=\n|$)', stripped)
            if tag_match:
                tag = tag_match.group(1).strip()
                if tag in old_tags:
                    is_old_tag_line = True

        if not is_old_tag_line:
            new_lines.append(line)

    return '\n'.join(new_lines)


def process_file(filepath):
    """处理单个文件"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        existing_meta, body = extract_metadata(content)

        # 如果没有 frontmatter，添加新的
        if not existing_meta:
            # 提取旧格式标签
            old_tags = extract_old_tags(body)

            # 从正文中删除旧标签行
            if old_tags:
                body = remove_old_tags_from_body(body, old_tags)

            new_meta = create_frontmatter(None, filepath, old_tags)
            new_content = new_meta + '\n\n' + body
        else:
            # 已有 frontmatter，只更新 updated
            # 提取旧格式标签（虽然不太可能有，但要保持一致）
            old_tags = extract_old_tags(body)

            # 如果正文中有旧标签，删除它们
            if old_tags:
                body = remove_old_tags_from_body(body, old_tags)

            new_meta = create_frontmatter(existing_meta, filepath, old_tags)
            new_content = new_meta + '\n\n' + body

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

        print(f"[OK] {filepath.name}")
        return True

    except Exception as e:
        print(f"[FAIL] {filepath}: {e}")
        return False


def main():
    if len(sys.argv) < 2:
        print("使用方法: python add_metadata.py <笔记目录或文件>")
        sys.exit(1)

    target = Path(sys.argv[1])

    if not target.exists():
        print(f"[FAIL] 路径不存在: {target}")
        sys.exit(1)

    if target.is_file():
        # 单个文件
        if target.suffix == '.md':
            process_file(target)
        else:
            print(f"[FAIL] 非 markdown 文件: {target}")
    else:
        # 目录
        md_files = list(target.rglob('*.md'))

        if not md_files:
            print(f"[FAIL] 未找到 markdown 文件: {target}")
            sys.exit(1)

        print(f"找到 {len(md_files)} 个文件")
        print("-" * 50)

        success_count = 0
        for filepath in md_files:
            if process_file(filepath):
                success_count += 1

        print("-" * 50)
        print(f"成功处理 {success_count}/{len(md_files)} 个文件")


if __name__ == '__main__':
    main()
