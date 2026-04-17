#!/usr/bin/env python3
"""
根据笔记内容智能建议分类和标签

使用方法：
    python categorize_note.py <笔记文件>

功能：
    - 分析笔记内容关键词
    - 建议合适的分类
    - 推荐相关标签（符合 SKILL.md 新格式）
    - 不直接修改文件，仅输出建议
"""

import sys
import re
from pathlib import Path
from collections import Counter


# 关键词映射表 - 符合 SKILL.md 新标签格式
# 格式：关键词 -> (标签列表, 分类)
KEYWORD_MAPPING = {
    # 容器相关 - 使用 K8S, Docker 等直接标签
    'docker': (['Docker', '容器化'], '云原生/Docker'),
    'dockerfile': (['Dockerfile', 'Docker'], '云原生/Docker'),
    'kubernetes': (['K8S', '容器编排'], '云原生/K8S'),
    'k8s': (['K8S', '容器编排'], '云原生/K8S'),
    'kubectl': (['K8S', 'kubectl'], '云原生/K8S'),
    'pod': (['K8S/Pod'], '云原生/K8S'),
    'deployment': (['K8S/Deployment'], '云原生/K8S'),
    'service': (['K8S/Service'], '云原生/K8S'),
    'ingress': (['K8S/Ingress'], '云原生/K8S'),
    'configmap': (['K8S/ConfigMap'], '云原生/K8S'),
    'secret': (['K8S/Secret'], '云原生/K8S'),
    'helm': (['Helm', 'K8S'], '云原生/K8S'),

    # CI/CD
    'jenkins': (['Jenkins', 'CI-CD'], 'CI-CD/Jenkins'),
    'gitlab': (['GitLab', 'CI-CD'], 'CI-CD/GitLab'),
    'github': (['GitHub', 'CI-CD'], 'CI-CD/GitHub'),
    'pipeline': (['CI-CD/流水线', '自动化'], 'CI-CD'),
    'cicd': (['CI-CD'], 'CI-CD'),

    # 云服务
    'aws': (['AWS', '云服务'], '云服务/AWS'),
    'azure': (['Azure', '云服务'], '云服务/Azure'),
    'gcp': (['GCP', '云服务'], '云服务/GCP'),
    'aliyun': (['阿里云', '云服务'], '云服务/阿里云'),
    'tencent': (['腾讯云', '云服务'], '云服务/腾讯云'),
    'ec2': (['AWS/EC2'], '云服务/AWS'),
    's3': (['AWS/S3'], '云服务/AWS'),
    'lambda': (['AWS/Lambda'], '云服务/AWS'),

    # 监控
    'prometheus': (['Prometheus', '监控'], '监控/Prometheus'),
    'grafana': (['Grafana', '监控'], '监控/Grafana'),
    'alertmanager': (['Prometheus', 'Alertmanager'], '监控/Prometheus'),
    'elk': (['ELK', '日志'], '监控/ELK'),
    'elasticsearch': (['Elasticsearch', '搜索引擎'], '数据库/Elasticsearch'),
    'logstash': (['ELK', 'Logstash'], '监控/ELK'),
    'kibana': (['ELK', 'Kibana'], '监控/ELK'),
    'monitoring': (['监控'], '监控'),
    'alert': (['监控告警'], '监控'),

    # 数据库
    'mysql': (['MySQL', '数据库'], '数据库/MySQL'),
    'mariadb': (['MariaDB', '数据库'], '数据库/MySQL'),
    'postgresql': (['PostgreSQL', '数据库'], '数据库/PostgreSQL'),
    'redis': (['Redis', '缓存'], '数据库/Redis'),
    'mongodb': (['MongoDB', 'NoSQL'], '数据库/MongoDB'),
    'oracle': (['Oracle', '数据库'], '数据库/Oracle'),
    'sqlserver': (['SQL Server', '数据库'], '数据库/SQLServer'),

    # 消息队列
    'kafka': (['Kafka', '消息队列'], '中间件/Kafka'),
    'rabbitmq': (['RabbitMQ', '消息队列'], '中间件/RabbitMQ'),
    'rocketmq': (['RocketMQ', '消息队列'], '中间件/RocketMQ'),

    # 中间件
    'nginx': (['Nginx', '中间件'], '中间件/Nginx'),
    'apache': (['Apache', '中间件'], '中间件/Apache'),
    'tomcat': (['Tomcat', '中间件'], '中间件/Tomcat'),
    'jetty': (['Jetty', '中间件'], '中间件/Jetty'),
    'zookeeper': (['Zookeeper', '中间件'], '中间件/Zookeeper'),

    # 编程语言
    'python': (['Python', '编程'], '编程/Python'),
    'java': (['Java', '编程'], '编程/Java'),
    'javascript': (['JavaScript', '编程'], '编程/JavaScript'),
    'typescript': (['TypeScript', '编程'], '编程/TypeScript'),
    'golang': (['Go', '编程'], '编程/Go'),
    'rust': (['Rust', '编程'], '编程/Rust'),
    'shell': (['Shell', '编程'], '编程/Shell'),
    'bash': (['Shell', 'Bash'], '编程/Shell'),
    'powershell': (['PowerShell', '编程'], '编程/PowerShell'),

    # 领域/场景 - 直接使用中文标签
    '故障排查': (['故障排查'], 'SRE'),
    'troubleshooting': (['故障排查'], 'SRE'),
    '问题': (['故障排查'], 'SRE'),
    '排错': (['故障排查'], 'SRE'),
    'sop': (['SOP', '标准流程'], '运维/SOP'),
    'tutorial': (['教程'], '知识'),
    '最佳实践': (['最佳实践'], '知识'),
    '架构': (['架构设计'], '架构'),
    'architecture': (['架构设计'], '架构'),
    '部署': (['安装配置', '部署'], '运维'),
    'deploy': (['安装配置', '部署'], '运维'),
    '安装': (['安装配置'], '运维'),
    '配置': (['配置'], '运维'),
    '监控': (['监控'], '监控'),
    '安全': (['安全'], '安全'),
    'security': (['安全'], '安全'),
    '备份': (['备份'], '运维'),
    'backup': (['备份'], '运维'),
    '优化': (['性能优化'], '性能'),
    'performance': (['性能优化'], '性能'),
    '网络': (['网络配置'], '网络'),
    'network': (['网络配置'], '网络'),

    # Linux/系统
    'linux': (['Linux'], 'SRE/Linux'),
    'centos': (['CentOS', 'Linux'], 'SRE/Linux'),
    'ubuntu': (['Ubuntu', 'Linux'], 'SRE/Linux'),
    'RHEL': (['RHEL', 'Linux'], 'SRE/Linux'),
    'redhat': (['RedHat', 'Linux'], 'SRE/Linux'),
    'windows': (['Windows'], '运维/Windows'),
    'macos': (['macOS'], '运维/macOS'),

    # 虚拟化/容器
    'vmware': (['VMware', '虚拟化'], '虚拟化/VMware'),
    'esxi': (['ESXi', '虚拟化'], '虚拟化/ESXi'),
    'hyperv': (['Hyper-V', '虚拟化'], '虚拟化/HyperV'),
    'virtualbox': (['VirtualBox', '虚拟化'], '虚拟化/VirtualBox'),

    # 工具类
    'git': (['Git'], '工具/Git'),
    'maven': (['Maven', '构建'], '工具/Maven'),
    'gradle': (['Gradle', '构建'], '工具/Gradle'),
    'ansible': (['Ansible', '自动化'], '运维/Ansible'),
    'terraform': (['Terraform', 'IaC'], '运维/Terraform'),
    'vagrant': (['Vagrant', '开发环境'], '工具/Vagrant'),
}


def extract_keywords(content):
    """从内容中提取关键词"""
    # 转换为小写
    content_lower = content.lower()

    # 移除代码块
    content_without_code = re.sub(r'```[\s\S]*?```', '', content_lower, flags=re.DOTALL)
    content_without_code = re.sub(r'`[^`]+`', '', content_without_code)

    # 提取英文单词
    words = re.findall(r'\b[a-z]{2,}\b', content_without_code)

    # 同时提取中文关键词
    chinese_pattern = re.findall(r'[\u4e00-\u9fa5]+', content)
    chinese_keywords = [w for w in chinese_pattern if len(w) >= 2]

    # 统计词频
    word_count = Counter(words)
    chinese_count = Counter(chinese_keywords)

    return word_count, chinese_count


def suggest_metadata(content, filepath):
    """根据内容建议元数据"""
    word_freq, chinese_freq = extract_keywords(content)
    suggested_tags = []
    suggested_category = None

    # 检查文件名中的关键词（优先）
    filename = Path(filepath).stem.lower()

    for keyword, (tags, cat) in KEYWORD_MAPPING.items():
        if keyword in filename:
            for tag in tags:
                if tag not in suggested_tags:
                    suggested_tags.insert(0, tag)
            if not suggested_category and cat:
                suggested_category = cat

    # 检查内容中的英文关键词
    for keyword, (tags, cat) in KEYWORD_MAPPING.items():
        count = word_freq.get(keyword.lower(), 0)
        if count > 0:
            for tag in tags:
                if tag not in suggested_tags:
                    suggested_tags.append(tag)
            if not suggested_category and cat:
                suggested_category = cat

    # 检查内容中的中文关键词
    for keyword, (tags, cat) in KEYWORD_MAPPING.items():
        if keyword in chinese_freq:
            for tag in tags:
                if tag not in suggested_tags:
                    suggested_tags.append(tag)
            if not suggested_category and cat:
                suggested_category = cat

    # 如果没有找到分类，使用文件名推断
    if not suggested_category:
        category = infer_category_from_filename(filepath)
        suggested_category = category

    # 去重并限制数量
    seen = set()
    unique_tags = []
    for tag in suggested_tags:
        if tag not in seen:
            seen.add(tag)
            unique_tags.append(tag)

    return unique_tags[:8], suggested_category


def infer_category_from_filename(filepath):
    """从文件名推断分类"""
    filename = Path(filepath).stem.lower()

    # 常见分类模式
    patterns = {
        'k8s': '云原生/K8S',
        'kubernetes': '云原生/K8S',
        'docker': '云原生/Docker',
        'linux': 'SRE/Linux',
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
        '故障': 'SRE/故障排查',
        '排错': 'SRE/故障排查',
    }

    for pattern, cat in patterns.items():
        if pattern in filename:
            return cat

    return '未分类'


def main():
    if len(sys.argv) < 2:
        print("使用方法: python categorize_note.py <笔记文件>")
        sys.exit(1)

    filepath = Path(sys.argv[1])

    if not filepath.exists():
        print(f"[FAIL] 文件不存在: {filepath}")
        sys.exit(1)

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        tags, category = suggest_metadata(content, filepath)

        print("=" * 60)
        print(f"[FILE] {filepath.name}")
        print("=" * 60)
        print()
        print("建议分类 (category):")
        print(f"  {category or '未分类'}")
        print()
        print("建议标签 (tags):")
        if tags:
            for tag in tags[:8]:
                print(f"  - {tag}")
        else:
            print("  (未找到明确的关键词)")
        print()
        print("建议的元数据:")
        print("---")
        print("tags:")
        for tag in tags[:8]:
            print(f"  - {tag}")
        print(f"category: {category or '未分类'}")
        print("---")
        print()
        print("[TIP]")
        print("  - 标签数量建议 3-7 个")
        print("  - 可以根据笔记内容调整建议的标签")
        print("  - 考虑添加 difficulty、importance、status 等可选字段")

    except Exception as e:
        print(f"[FAIL] 错误: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
