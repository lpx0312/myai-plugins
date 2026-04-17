#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ESXI VM Creator - Trigger Jenkins builds and monitor status
Compatible with Python 2.7+ and Python 3.x
Standard library only
"""

from __future__ import print_function
import sys
import json
import base64
import time

# Python 2/3 compatibility
try:
    from urllib.request import Request, urlopen
    from urllib.error import HTTPError, URLError
    from urllib.parse import urlencode
except ImportError:
    from urllib2 import Request, urlopen, HTTPError, URLError
    from urllib import urlencode

# Jenkins configuration
JENKINS_URL = "http://192.168.0.11:8080"
USERNAME = "lipanxiang"

# API Tokens
TOKENS = {
    "192.168.0.3": "11a53f38acf09e8d34b3ca4255bf3449b1",
    "192.168.0.200": "",  # TODO: Add token
}

# Job names
JOBS = {
    "192.168.0.3": "ESXI_clone_multi",
    "192.168.0.200": "ESXI_clone_multi_200",
}

# Default timeouts
DEFAULT_TIMEOUT = 1200      # 20 minutes
DEFAULT_QUEUE_TIMEOUT = 300 # 5 minutes
DEFAULT_INTERVAL = 10       # 10 seconds
HTTP_TIMEOUT = 30           # 30 seconds


def get_auth_header(esxi_ip):
    """Build Basic Auth header"""
    token = TOKENS.get(esxi_ip, "")
    if not token:
        return None
    auth_str = "{}:{}".format(USERNAME, token)
    if sys.version_info[0] >= 3:
        return base64.b64encode(auth_str.encode()).decode()
    else:
        return base64.b64encode(auth_str)


def get_crumb(esxi_ip):
    """Get Jenkins CSRF crumb"""
    auth = get_auth_header(esxi_ip)
    if not auth:
        return {}

    url = "{}/crumbIssuer/api/json".format(JENKINS_URL)
    req = Request(url)
    req.add_header("Authorization", "Basic {}".format(auth))

    try:
        response = urlopen(req, timeout=HTTP_TIMEOUT)
        data = json.loads(response.read().decode())
        return {data["crumbRequestField"]: data["crumb"]}
    except Exception:
        return {}


def make_request(url, esxi_ip, data=None, retry=2):
    """
    Make HTTP request with retry
    Returns (response_data, error)
    """
    auth = get_auth_header(esxi_ip)
    if not auth:
        return None, {"error": "auth_failed", "message": "No API token for {}".format(esxi_ip)}

    # Get crumb for POST requests
    crumb_headers = get_crumb(esxi_ip) if data else {}

    for attempt in range(retry + 1):
        try:
            if data:
                post_data = urlencode(data)
                if sys.version_info[0] >= 3:
                    post_data = post_data.encode()
                req = Request(url, data=post_data)
                req.add_header("Content-Type", "application/x-www-form-urlencoded")
            else:
                req = Request(url)

            req.add_header("Authorization", "Basic {}".format(auth))
            for key, value in crumb_headers.items():
                req.add_header(key, value)

            response = urlopen(req, timeout=HTTP_TIMEOUT)
            content = response.read()
            if sys.version_info[0] >= 3:
                content = content.decode()
            return {"content": content, "headers": dict(response.headers), "code": response.getcode()}, None

        except HTTPError as e:
            if e.code in [401, 403]:
                return None, {"error": "auth_failed", "message": "Authentication failed (HTTP {})".format(e.code)}
            elif e.code == 404:
                return None, {"error": "not_found", "message": "Resource not found (HTTP 404)"}
            elif attempt < retry:
                time.sleep(3)
                continue
            return None, {"error": "http_error", "message": "HTTP {} {}".format(e.code, e.reason)}
        except URLError as e:
            if attempt < retry:
                time.sleep(3)
                continue
            return None, {"error": "network_error", "message": str(e.reason)}
        except Exception as e:
            return None, {"error": "unknown_error", "message": str(e)}

    return None, {"error": "network_error", "message": "Max retries exceeded"}


def trigger_build(esxi_ip, yaml_content):
    """
    Trigger Jenkins build
    Returns (queue_url, error)
    """
    if esxi_ip not in JOBS:
        return None, {"error": "invalid_esxi", "message": "Unknown ESXI server: {}".format(esxi_ip)}

    job_name = JOBS[esxi_ip]
    url = "{}/job/{}/buildWithParameters".format(JENKINS_URL, job_name)

    result, err = make_request(url, esxi_ip, data={"Host_file": yaml_content})
    if err:
        return None, err

    queue_url = result["headers"].get("Location", "")
    if not queue_url:
        # Try to get from response
        queue_url = result["headers"].get("location", "")

    return queue_url, None


def get_queue_status(queue_url, esxi_ip):
    """
    Get queue item status
    Returns queue info dict
    """
    url = "{}/api/json".format(queue_url.rstrip("/"))
    result, err = make_request(url, esxi_ip)
    if err:
        return None, err

    try:
        data = json.loads(result["content"])
        return data, None
    except Exception as e:
        return None, {"error": "parse_error", "message": str(e)}


def get_build_status(build_url, esxi_ip):
    """
    Get build status
    Returns build info dict
    """
    url = "{}/api/json".format(build_url.rstrip("/"))
    result, err = make_request(url, esxi_ip)
    if err:
        return None, err

    try:
        data = json.loads(result["content"])
        return data, None
    except Exception as e:
        return None, {"error": "parse_error", "message": str(e)}


def get_console_tail(build_url, esxi_ip, lines=50):
    """
    Get last N lines of console output
    """
    url = "{}/logText/progressiveText?start=0".format(build_url.rstrip("/"))
    result, err = make_request(url, esxi_ip)
    if err:
        return []

    try:
        content = result["content"]
        all_lines = content.split("\n")
        return all_lines[-lines:] if len(all_lines) > lines else all_lines
    except Exception:
        return []


def wait_for_build(queue_url, esxi_ip, timeout=DEFAULT_TIMEOUT,
                   queue_timeout=DEFAULT_QUEUE_TIMEOUT, interval=DEFAULT_INTERVAL):
    """
    Wait for build to complete
    Returns result dict
    """
    start_time = time.time()
    job_name = JOBS.get(esxi_ip, "unknown")

    # Phase 1: Wait for build to start (leave queue)
    log_stderr("[INFO] Waiting for build to start...")
    build_url = None
    build_number = None

    while time.time() - start_time < queue_timeout:
        queue_info, err = get_queue_status(queue_url, esxi_ip)
        if err:
            # Network error, retry
            time.sleep(interval)
            continue

        if queue_info.get("cancelled", False):
            return {
                "success": False,
                "error": "cancelled",
                "message": "Build was cancelled while in queue",
                "queue_url": queue_url
            }

        executable = queue_info.get("executable")
        if executable:
            build_url = executable.get("url", "")
            build_number = executable.get("number")
            break

        time.sleep(interval)
    else:
        return {
            "success": False,
            "error": "queue_timeout",
            "message": "Build did not start within {} seconds".format(queue_timeout),
            "queue_url": queue_url
        }

    if not build_url:
        return {
            "success": False,
            "error": "unknown",
            "message": "Could not get build URL from queue",
            "queue_url": queue_url
        }

    log_stderr("[INFO] Build #{} started, waiting for completion...".format(build_number))

    # Phase 2: Wait for build to complete
    build_start_time = time.time()
    last_duration = 0

    while time.time() - start_time < timeout:
        build_info, err = get_build_status(build_url, esxi_ip)
        if err:
            time.sleep(interval)
            continue

        building = build_info.get("building", False)
        result_str = build_info.get("result", "")
        duration = build_info.get("duration", 0) // 1000  # ms to seconds

        # Log progress every interval
        if building:
            elapsed = int(time.time() - build_start_time)
            if elapsed - last_duration >= interval:
                log_stderr("[INFO] [{}s] Building...".format(elapsed))
                last_duration = elapsed
            time.sleep(interval)
            continue

        # Build completed
        success = result_str == "SUCCESS"
        duration = build_info.get("duration", 0) // 1000

        result = {
            "success": success,
            "mode": "sync",
            "esxi": esxi_ip,
            "job": job_name,
            "build_number": build_number,
            "build_url": build_url,
            "duration": duration,
            "queue_url": queue_url
        }

        if success:
            log_stderr("[SUCCESS] Build #{} completed in {}s".format(build_number, duration))
        else:
            log_stderr("[FAILED] Build #{} failed after {}s".format(build_number, duration))
            console_tail = get_console_tail(build_url, esxi_ip)
            result["error"] = "build_failed"
            result["console_tail"] = console_tail

        return result

    # Timeout
    return {
        "success": False,
        "error": "timeout",
        "message": "Build did not complete within {} seconds".format(timeout),
        "queue_url": queue_url,
        "build_url": build_url,
        "build_number": build_number
    }


def check_status_only(queue_url, esxi_ip):
    """
    Check build status without waiting
    """
    # First check queue
    queue_info, err = get_queue_status(queue_url, esxi_ip)
    if err:
        return {"success": False, "error": err.get("error", "unknown"), "message": err.get("message", "")}

    if queue_info.get("cancelled", False):
        return {
            "status": "cancelled",
            "success": False,
            "queue_url": queue_url
        }

    executable = queue_info.get("executable")
    if not executable:
        return {
            "status": "queued",
            "queue_url": queue_url,
            "why": queue_info.get("why", "")
        }

    build_url = executable.get("url", "")
    build_number = executable.get("number")

    # Check build status
    build_info, err = get_build_status(build_url, esxi_ip)
    if err:
        return {"success": False, "error": err.get("error", "unknown"), "message": err.get("message", "")}

    building = build_info.get("building", False)
    result_str = build_info.get("result", "")

    if building:
        return {
            "status": "building",
            "build_number": build_number,
            "build_url": build_url,
            "duration": build_info.get("duration", 0) // 1000
        }

    return {
        "status": "completed",
        "success": result_str == "SUCCESS",
        "build_number": build_number,
        "build_url": build_url,
        "duration": build_info.get("duration", 0) // 1000,
        "result": result_str
    }


def log_stderr(msg):
    """Print to stderr"""
    print(msg, file=sys.stderr)


def print_usage():
    """Print usage information"""
    print("""
Usage:
  esxi_vm_creator.py --esxi <IP> --yaml <YAML> [options]
  esxi_vm_creator.py --esxi <IP> --file <FILE> [options]
  esxi_vm_creator.py --status --queue-url <URL>

Required:
  --esxi <IP>        ESXI server IP (192.168.0.3 | 192.168.0.200)
  --yaml <YAML>      YAML config content (string)
  --file <FILE>      YAML config file path

Mode options:
  --async            Async mode, trigger without waiting
  --status           Check build status mode (requires --queue-url)
  --queue-url <URL>  Queue URL to check

Timeout options:
  --timeout <SEC>    Build timeout (default: 1200 = 20min)
  --queue-timeout <SEC>  Queue timeout (default: 300 = 5min)
  --interval <SEC>   Poll interval (default: 10)

Other:
  --help             Show this help

Exit codes:
  0 = Success
  1 = Build failed
  2 = Invalid arguments
  3 = Network error
  4 = Timeout
""")


def main():
    """Main function"""
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        print_usage()
        sys.exit(0)

    # Parse arguments
    params = {
        "esxi_ip": None,
        "yaml_content": None,
        "async_mode": False,
        "status_mode": False,
        "queue_url": None,
        "timeout": DEFAULT_TIMEOUT,
        "queue_timeout": DEFAULT_QUEUE_TIMEOUT,
        "interval": DEFAULT_INTERVAL,
    }

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--esxi" and i + 1 < len(args):
            params["esxi_ip"] = args[i + 1]
            i += 2
        elif arg == "--yaml" and i + 1 < len(args):
            params["yaml_content"] = args[i + 1]
            i += 2
        elif arg == "--file" and i + 1 < len(args):
            try:
                mode = "r"
                if sys.version_info[0] >= 3:
                    mode = "r"
                with open(args[i + 1], mode) as f:
                    params["yaml_content"] = f.read()
            except Exception as e:
                output = {"success": False, "error": "file_error", "message": str(e)}
                print(json.dumps(output, indent=2))
                sys.exit(2)
            i += 2
        elif arg == "--async":
            params["async_mode"] = True
            i += 1
        elif arg == "--status":
            params["status_mode"] = True
            i += 1
        elif arg == "--queue-url" and i + 1 < len(args):
            params["queue_url"] = args[i + 1]
            i += 2
        elif arg == "--timeout" and i + 1 < len(args):
            params["timeout"] = int(args[i + 1])
            i += 2
        elif arg == "--queue-timeout" and i + 1 < len(args):
            params["queue_timeout"] = int(args[i + 1])
            i += 2
        elif arg == "--interval" and i + 1 < len(args):
            params["interval"] = int(args[i + 1])
            i += 2
        else:
            i += 1

    # Status check mode
    if params["status_mode"]:
        if not params["queue_url"]:
            output = {"success": False, "error": "missing_queue_url", "message": "--queue-url is required for status mode"}
            print(json.dumps(output, indent=2))
            sys.exit(2)

        esxi_ip = params["esxi_ip"] or "192.168.0.3"  # Default to ESXI-3
        result = check_status_only(params["queue_url"], esxi_ip)
        print(json.dumps(result, indent=2))
        sys.exit(0 if result.get("success", True) else 1)

    # Build mode - validate required params
    if not params["esxi_ip"]:
        output = {"success": False, "error": "missing_esxi", "message": "--esxi is required"}
        print(json.dumps(output, indent=2))
        sys.exit(2)

    if not params["yaml_content"]:
        output = {"success": False, "error": "missing_yaml", "message": "--yaml or --file is required"}
        print(json.dumps(output, indent=2))
        sys.exit(2)

    esxi_ip = params["esxi_ip"]
    job_name = JOBS.get(esxi_ip, "unknown")

    log_stderr("[INFO] Triggering build on {} ({})...".format(esxi_ip, job_name))

    # Trigger build
    queue_url, err = trigger_build(esxi_ip, params["yaml_content"])
    if err:
        output = {"success": False, "mode": "trigger"}
        output.update(err)
        print(json.dumps(output, indent=2))
        sys.exit(3)

    log_stderr("[INFO] Build queued: {}".format(queue_url))

    # Async mode - return immediately
    if params["async_mode"]:
        output = {
            "success": True,
            "mode": "async",
            "esxi": esxi_ip,
            "job": job_name,
            "queue_url": queue_url
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    # Sync mode - wait for completion
    result = wait_for_build(
        queue_url,
        esxi_ip,
        timeout=params["timeout"],
        queue_timeout=params["queue_timeout"],
        interval=params["interval"]
    )

    print(json.dumps(result, indent=2))

    # Exit with appropriate code
    if result.get("success"):
        sys.exit(0)
    elif result.get("error") in ["timeout", "queue_timeout"]:
        sys.exit(4)
    elif result.get("error") in ["network_error", "auth_failed"]:
        sys.exit(3)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
