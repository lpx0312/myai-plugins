#!/usr/bin/env python3
"""
批量更新笔记的 updated 时间戳

使用方法：
    python update_timestamps.py <笔记目录或文件>

功能：
    - 批量更新所有笔记的 updated 字段
    - 如果没有 updated 字段，自动添加
    - 如果没有 frontmatter，自动创建
    - 保留其他元数据不变
"""

import os
import sys
from datetime import datetime
from pathlib import Path
import re


def extract_frontmatter(content):
    """提取 frontmatter 和 body，返回 (frontmatter字符串, body字符串)"""
    if content.startswith('---'):
        # 找到第二个 --- 的位置
        end = content.find('---', 3)
        if end != -1:
            frontmatter = content[3:end].strip()
            body = content[end+3:]
            return frontmatter, body
    return None, content


def update_timestamp(content):
    """更新或添加 updated 时间戳"""
    now = datetime.now().strftime('%Y-%m-%d')

    frontmatter, body = extract_frontmatter(content)

    if not frontmatter:
        # 没有 frontmatter，创建一个
        new_meta = f"""---
updated: {now}
---

"""
        return new_meta + content

    # 已有 frontmatter，解析并更新
    lines = frontmatter.split('\n')
    has_updated = False
    result_lines = []

    for line in lines:
        if line.strip().startswith('updated:'):
            result_lines.append(f'updated: {now}')
            has_updated = True
        else:
            result_lines.append(line)

    if not has_updated:
        # 找到合适的位置插入 updated（通常在 created 之后）
        inserted = False
        for i, line in enumerate(result_lines):
            if line.strip().startswith('created:'):
                result_lines.insert(i + 1, f'updated: {now}')
                inserted = True
                break
        if not inserted:
            result_lines.append(f'updated: {now}')

    new_frontmatter = '\n'.join(result_lines)
    return f"---\n{new_frontmatter}\n---\n{body}"


def process_file(filepath):
    """处理单个文件"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # 检查是否需要更新
        frontmatter, _ = extract_frontmatter(content)
        needs_update = False

        if not frontmatter:
            needs_update = True
        else:
            # 检查是否有 updated 字段且是否是今天
            today = datetime.now().strftime('%Y-%m-%d')
            if f'updated: {today}' not in frontmatter:
                needs_update = True

        if not needs_update:
            print(f"[SKIP] {filepath.name} (已是最新)")
            return True

        new_content = update_timestamp(content)

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

        print(f"[OK] {filepath.name}")
        return True

    except Exception as e:
        print(f"[FAIL] {filepath.name}: {e}")
        return False


def main():
    if len(sys.argv) < 2:
        print("使用方法: python update_timestamps.py <笔记目录或文件>")
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
        print(f"成功更新 {success_count}/{len(md_files)} 个文件")


if __name__ == '__main__':
    main()
