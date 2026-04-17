#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ESXI connectivity check script
Compatible with Python 2.7+ and Python 3.x
Standard library only
"""

from __future__ import print_function
import subprocess
import sys
import json

# ESXI server list
ESXI_SERVERS = [
    "192.168.0.3",
    "192.168.0.200",
]


def ping_once(host, timeout=1):
    """
    Single ping check
    Returns True/False
    """
    try:
        # Windows ping command
        cmd = ["ping", "-n", "1", "-w", str(timeout * 1000), host]
        result = subprocess.call(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return result == 0
    except Exception:
        return False


def ping(host, retries=3, timeout=1):
    """
    Check if host is reachable with retry mechanism
    Strict mode: ALL retries must succeed to be considered reachable
    Returns True/False
    """
    for i in range(retries):
        if not ping_once(host, timeout):
            # If any ping fails, host is unreachable
            return False
    # All pings succeeded
    return True


def check_all():
    """
    Check connectivity of all ESXI servers
    Returns dict: {"ip": True/False, ...}
    """
    results = {}
    for esxi_ip in ESXI_SERVERS:
        results[esxi_ip] = ping(esxi_ip)
    return results


def main():
    """Main function"""
    # Check connectivity
    results = check_all()

    # Output JSON format to stdout (for machine parsing)
    output = json.dumps(results)
    print(output)

    # Output human readable format to stderr (for debugging)
    print("", file=sys.stderr)
    for ip, status in results.items():
        status_text = "reachable" if status else "unreachable"
        print("  {}: {}".format(ip, status_text), file=sys.stderr)

    return results


if __name__ == "__main__":
    main()
