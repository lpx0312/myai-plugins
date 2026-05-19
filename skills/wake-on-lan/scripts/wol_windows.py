# wol_windows.py - Wake-on-LAN using Scapy Layer 2 Ether frame
# Usage: python wol_windows.py <主机名或MAC地址>
# Supported hosts: esxi200, xp, r3600, all
# Requires: pip install scapy
import sys
import time
import subprocess
import argparse
from scapy.all import *

# 主机配置
HOSTS = {
    "esxi200": {"mac": "22:02:4d:07:5c:7a", "ip": "192.168.0.200"},
    "xp":      {"mac": "1C:83:41:8A:4E:7B", "ip": "192.168.0.225"},
    "r3600":   {"mac": "2C:F0:5D:3D:27:87", "ip": "192.168.0.198"},
}

def send_wol(mac_str):
    mac = mac_str.replace(":", "").replace("-", "").replace(".", "")
    if len(mac) != 12:
        print(f"Error: invalid MAC address: {mac_str}")
        sys.exit(1)
    mac_bytes = bytes.fromhex(mac)
    packet_bytes = b'\xff' * 6 + mac_bytes * 16

    iface = get_default_interface()
    print(f"Using interface: {iface}")
    print(f"Sending WoL magic packet to {mac_str} via broadcast Ether frame...")
    sendp(Ether(dst="ff:ff:ff:ff:ff:ff")/Raw(load=packet_bytes), iface=iface, verbose=0)
    print("Done!")

def get_default_interface():
    try:
        return conf.iface
    except:
        pass
    from scapy.arch.windows import get_interface_list
    ifaces = get_interface_list()
    for iface in ifaces:
        if "Ethernet" in str(iface) or "ethernet" in str(iface):
            return iface
    for iface in ifaces:
        if "Loopback" not in str(iface) and "loopback" not in str(iface):
            return iface
    return ifaces[0] if ifaces else "Ethernet"

def ping_host(ip):
    try:
        subprocess.check_output(
            ["ping", "-n", "1", "-w", "2000", ip],
            stderr=subprocess.STDOUT
        )
        return True
    except subprocess.CalledProcessError:
        return False

def verify_host(name, ip, max_wait=180, interval=10):
    print(f"\nWaiting for {name} to come online (max {max_wait}s)...")
    elapsed = 0
    while elapsed < max_wait:
        time.sleep(interval)
        elapsed += interval
        print(f"[{elapsed}s] Checking {name} ({ip})...", end=" ")
        if ping_host(ip):
            print("Online")
            print(f"\n{name} is online! (took {elapsed}s)")
            return True
        else:
            print("Offline")
    print(f"\nTimeout: {name} did not come online within {max_wait}s")
    return False

def wake_host(name):
    if name == "all":
        for host_name, info in HOSTS.items():
            print(f"Waking {host_name} ({info['mac']})")
            send_wol(info["mac"])
        print("\nAll wake packets sent.")
        print("Wait 1-3 minutes, then verify manually:")
        for host_name, info in HOSTS.items():
            print(f"  ping -n 1 {info['ip']}  # {host_name}")
        return

    if name not in HOSTS:
        print(f"Unknown host: {name}")
        print("Available hosts:")
        for h, info in HOSTS.items():
            print(f"  - {h} ({info['ip']})")
        print("  - all (wake all hosts)")
        sys.exit(1)

    info = HOSTS[name]
    mac, ip = info["mac"], info["ip"]

    # Check if already online
    print(f"Checking {name} ({ip})...", end=" ")
    if ping_host(ip):
        print("Already online")
        return

    # Send WOL and verify
    print("Offline")
    send_wol(mac)
    verify_host(name, ip)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Wake-on-LAN using Scapy (Windows)")
    parser.add_argument("host", help="Hostname (esxi200/xp/r3600/all) or MAC address")
    args = parser.parse_args()

    if args.host in HOSTS or args.host == "all":
        wake_host(args.host)
    else:
        # Treat as raw MAC address
        send_wol(args.host)
