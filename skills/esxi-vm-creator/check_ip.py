#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
IP conflict detection script
Compatible with Python 2.7+ and Python 3.x
Standard library only

Uses strict strategy: multiple pings, ALL must succeed to be considered in use
This avoids false positives from Windows ping bug
"""

from __future__ import print_function
import subprocess
import sys
import json
import re


def ping_once(ip, timeout=1):
    """
    Single ping check
    Returns True/False
    """
    try:
        # Windows ping command
        cmd = ["ping", "-n", "1", "-w", str(timeout * 1000), ip]
        result = subprocess.call(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return result == 0
    except Exception:
        return False


def ping_strict(ip, retries=3, timeout=1):
    """
    Strict ping check with multiple retries
    Returns True only if ALL pings succeed (IP is definitely in use)
    Returns False if ANY ping fails (IP is likely available)

    This avoids false positives from Windows ping bug
    """
    for i in range(retries):
        if not ping_once(ip, timeout):
            # If any ping fails, IP is not in use
            return False
    # All pings succeeded, IP is in use
    return True


def arp_check(ip):
    """
    Check ARP table for IP entry
    Returns True if found in ARP table, False otherwise
    """
    try:
        result = subprocess.Popen(
            ["arp", "-a"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        output, _ = result.communicate()
        if sys.version_info[0] >= 3:
            output = output.decode()

        # Look for the IP in ARP table
        pattern = r"\s*" + re.escape(ip) + r"\s+([0-9a-fA-F-]+)"
        match = re.search(pattern, output)
        return match is not None
    except Exception:
        return False


def check_ip(ip):
    """
    Check if IP is in use (conflict detection)
    Uses strict ping strategy + ARP check

    Returns dict: {"ip": str, "in_use": bool, "method": str}
    """
    # Method 1: Strict ping check (all retries must succeed)
    if ping_strict(ip):
        return {"ip": ip, "in_use": True, "method": "ping"}

    # Method 2: ARP check (for recently seen hosts)
    if arp_check(ip):
        return {"ip": ip, "in_use": True, "method": "arp"}

    return {"ip": ip, "in_use": False, "method": "none"}


def check_multiple_ips(ips):
    """
    Check multiple IPs for conflicts
    Returns dict: {"ip1": {"in_use": bool, "method": str}, ...}
    """
    results = {}
    for ip in ips:
        results[ip] = check_ip(ip)
    return results


def main():
    """Main function"""
    # Collect IPs to check
    ips_to_check = []

    i = 1
    while i < len(sys.argv):
        if sys.argv[i] in ["--ip", "-i"] and i + 1 < len(sys.argv):
            ips_to_check.append(sys.argv[i + 1])
            i += 2
        elif sys.argv[i] in ["--ips", "-I"] and i + 1 < len(sys.argv):
            ips_to_check.extend([ip.strip() for ip in sys.argv[i + 1].split(",")])
            i += 2
        elif sys.argv[i] in ["--file", "-f"] and i + 1 < len(sys.argv):
            try:
                with open(sys.argv[i + 1], "r") as f:
                    for line in f:
                        ip = line.strip()
                        if ip and not ip.startswith("#"):
                            ips_to_check.append(ip)
            except Exception as e:
                print(json.dumps({"error": str(e)}))
                sys.exit(1)
            i += 2
        elif sys.argv[i] in ["--help", "-h"]:
            print("Usage: python check_ip.py --ip <IP>")
            print("       python check_ip.py --ips <IP1,IP2,...>")
            print("       python check_ip.py --file <file_path>")
            sys.exit(0)
        else:
            i += 1

    # If no IP provided, show usage
    if not ips_to_check:
        print("Usage: python check_ip.py --ip <IP>")
        print("       python check_ip.py --ips <IP1,IP2,...>")
        print("       python check_ip.py --file <file_path>")
        print("")
        print("Examples:")
        print("  python check_ip.py --ip 192.168.1.190")
        print("  python check_ip.py --ips 192.168.1.190,192.168.1.191")
        sys.exit(1)

    # Check IPs
    if len(ips_to_check) == 1:
        result = check_ip(ips_to_check[0])
        print(json.dumps(result, indent=2))

        # Human readable output to stderr
        status = "IN USE" if result["in_use"] else "AVAILABLE"
        print("", file=sys.stderr)
        print("[IP Conflict Check] {}".format(ips_to_check[0]), file=sys.stderr)
        print("  Status: {}".format(status), file=sys.stderr)
        if result["in_use"]:
            print("  Method: {}".format(result["method"]), file=sys.stderr)
    else:
        results = check_multiple_ips(ips_to_check)
        print(json.dumps(results, indent=2))

        # Human readable output to stderr
        print("", file=sys.stderr)
        print("[IP Conflict Check] Multiple IPs", file=sys.stderr)
        for ip, data in results.items():
            status = "IN USE" if data["in_use"] else "AVAILABLE"
            print("  {}: {}".format(ip, status), file=sys.stderr)


if __name__ == "__main__":
    main()
