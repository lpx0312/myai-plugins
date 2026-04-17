#!/usr/bin/env python3
"""
Certificate Expiry Checker
批量检查SSL证书有效期，支持本地文件和远程URL
"""

import argparse
import ssl
import socket
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse

try:
    from cryptography import x509
    from cryptography.hazmat.backends import default_backend
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False


def parse_date(date_str):
    """解析OpenSSL输出的日期格式"""
    date_str = date_str.strip()
    formats = [
        "%b %d %H:%M:%S %Y %Z",
        "%b %d %H:%M:%S %Y GMT",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d"
    ]
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    raise ValueError(f"无法解析日期: {date_str}")


def check_cert_file(cert_path, warn_days=30):
    """检查本地证书文件"""
    path = Path(cert_path)
    if not path.exists():
        return None, f"文件不存在: {cert_path}"

    try:
        if HAS_CRYPTO:
            with open(path, 'rb') as f:
                cert = x509.load_pem_x509_certificate(f.read(), default_backend())
                not_after = cert.not_valid_after_utc.replace(tzinfo=None)
                not_before = cert.not_valid_before_utc.replace(tzinfo=None)
        else:
            # 使用OpenSSL
            result = subprocess.run(
                ['openssl', 'x509', '-in', str(path), '-dates', '-noout'],
                capture_output=True, text=True, check=True
            )
            dates = {}
            for line in result.stdout.strip().split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    dates[key.strip()] = parse_date(value.strip())

            not_before = dates.get('notBefore')
            not_before = not_before.replace(tzinfo=None) if not_before else None
            not_after = dates.get('notAfter')
            not_after = not_after.replace(tzinfo=None) if not_after else None

        if not_after is None:
            return None, f"无法解析证书有效期"

        now = datetime.now()
        days_left = (not_after - now).days

        status = "OK"
        if days_left < 0:
            status = "EXPIRED"
        elif days_left <= warn_days:
            status = "WARNING"

        return {
            'path': str(path),
            'not_before': not_before,
            'not_after': not_after,
            'days_left': days_left,
            'status': status
        }, None

    except Exception as e:
        return None, f"错误: {str(e)}"


def check_cert_url(url, warn_days=30, port=443):
    """检查远程服务器证书"""
    try:
        parsed = urlparse(url)
        hostname = parsed.hostname or url.split(':')[0]
        port = parsed.port or port

        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

        with socket.create_connection((hostname, port), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                cert_der = ssock.getpeercert(binary_form=True)

        if HAS_CRYPTO:
            cert = x509.load_der_x509_certificate(cert_der, default_backend())
            not_after = cert.not_valid_after_utc.replace(tzinfo=None)
            not_before = cert.not_valid_before_utc.replace(tzinfo=None)
        else:
            # 写入临时文件用OpenSSL解析
            import tempfile
            with tempfile.NamedTemporaryFile(mode='wb', suffix='.der', delete=False) as f:
                f.write(cert_der)
                temp_der = f.name

            try:
                result = subprocess.run(
                    ['openssl', 'x509', '-in', temp_der, '-inform', 'DER', '-dates', '-noout'],
                    capture_output=True, text=True, check=True
                )
                dates = {}
                for line in result.stdout.strip().split('\n'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        dates[key.strip()] = parse_date(value.strip())

                not_before = dates.get('notBefore')
                not_before = not_before.replace(tzinfo=None) if not_before else None
                not_after = dates.get('notAfter')
                not_after = not_after.replace(tzinfo=None) if not_after else None
            finally:
                Path(temp_der).unlink(missing_ok=True)

        if not_after is None:
            return None, f"无法解析证书有效期"

        now = datetime.now()
        days_left = (not_after - now).days

        status = "OK"
        if days_left < 0:
            status = "EXPIRED"
        elif days_left <= warn_days:
            status = "WARNING"

        return {
            'url': f"{hostname}:{port}",
            'not_before': not_before,
            'not_after': not_after,
            'days_left': days_left,
            'status': status
        }, None

    except socket.timeout:
        return None, f"连接超时: {url}"
    except socket.gaierror:
        return None, f"无法解析主机名: {hostname}"
    except Exception as e:
        return None, f"错误: {str(e)}"


def read_input_list(input_file):
    """读取输入文件列表"""
    items = []
    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                items.append(line)
    return items


def print_result(result):
    """打印检查结果"""
    status = result['status']
    days_left = result['days_left']

    if status == "EXPIRED":
        status_str = f"\033[91mEXPIRED ({days_left}天)\033[0m"
    elif status == "WARNING":
        status_str = f"\033[93mWARNING ({days_left}天)\033[0m"
    else:
        status_str = f"\033[92mOK ({days_left}天)\033[0m"

    if 'path' in result:
        print(f"  [{status_str}] {result['path']}")
        print(f"         过期时间: {result['not_after']}")
    else:
        print(f"  [{status_str}] {result['url']}")
        print(f"         过期时间: {result['not_after']}")


def main():
    parser = argparse.ArgumentParser(
        description='SSL证书有效期批量检查工具',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--file', '-f', help='检查单个证书文件')
    group.add_argument('--url', '-u', help='检查远程URL的证书')
    group.add_argument('--input', '-i', help='输入文件，每行一个证书路径或URL')

    parser.add_argument('--warn', '-w', type=int, default=30,
                        help='提前警告天数 (默认: 30)')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='只显示警告和过期证书')

    args = parser.parse_args()

    results = []
    errors = []

    if args.file:
        result, error = check_cert_file(args.file, args.warn)
        if error:
            errors.append(error)
        elif result:
            results.append(result)

    elif args.url:
        result, error = check_cert_url(args.url, args.warn)
        if error:
            errors.append(error)
        elif result:
            results.append(result)

    elif args.input:
        items = read_input_list(args.input)
        for item in items:
            item = item.strip()
            if not item:
                continue

            if item.startswith('http://') or item.startswith('https://') or '*://' in item:
                result, error = check_cert_url(item, args.warn)
            else:
                result, error = check_cert_file(item, args.warn)

            if error:
                errors.append(f"{item}: {error}")
            elif result:
                results.append(result)

    # 打印错误
    for error in errors:
        print(f"\033[91m[ERROR]\033[0m {error}", file=sys.stderr)

    # 打印结果
    print("\n证书有效期检查结果:")
    print("=" * 60)

    expired = [r for r in results if r['status'] == 'EXPIRED']
    warnings = [r for r in results if r['status'] == 'WARNING']
    ok = [r for r in results if r['status'] == 'OK']

    if not args.quiet:
        for r in ok:
            print_result(r)

    for r in warnings:
        print_result(r)

    for r in expired:
        print_result(r)

    print("=" * 60)
    print(f"总计: {len(results)} | 正常: {len(ok)} | 警告: {len(warnings)} | 过期: {len(expired)} | 错误: {len(errors)}")

    # 返回非零退出码表示有警告或错误
    sys.exit(1 if (warnings or expired or errors) else 0)


if __name__ == '__main__':
    main()
