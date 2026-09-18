#!/usr/bin/env python3
# Shared resolver: profile Apache by platform line (8.3 / 8.5).
# Import from web-* scripts. No Apache inside projects.
#
# Profile roots:
#   %USERPROFILE%\tools\apache-83  → port 8083  (v8version 8.3*)
#   %USERPROFILE%\tools\apache-85  → port 8085  (v8version 8.5*)
#
# Workspace overrides (autumn-properties.json):
#   vrunner.v8version, web.appName, web.port, web.apachePath

import json
import os
from urllib.parse import urlparse


def find_1c_project_root(start_dir=None):
    d = os.path.abspath(start_dir or os.getcwd())
    while True:
        if os.path.isfile(os.path.join(d, "autumn-properties.json")) or os.path.isfile(
            os.path.join(d, "env.json")
        ):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.abspath(start_dir or os.getcwd())
        d = parent


def read_1c_json(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


def app_name_from_web_url(web_url):
    if not web_url:
        return None
    try:
        path = urlparse(web_url).path or ""
        segs = [s for s in path.split("/") if s]
        return segs[0].lower() if segs else None
    except Exception:
        return None


def port_from_web_url(web_url):
    if not web_url:
        return None
    try:
        return urlparse(web_url).port
    except Exception:
        return None


def platform_apache_defaults(v8version):
    ver = (v8version or "8.3").strip()
    if ver.startswith("8.5"):
        return {
            "label": "85",
            "port": 8085,
            "apache_path": os.path.join(os.path.expanduser("~"), "tools", "apache-85"),
        }
    return {
        "label": "83",
        "port": 8083,
        "apache_path": os.path.join(os.path.expanduser("~"), "tools", "apache-83"),
    }


def resolve_1c_web_targets(
    project_root=None,
    v8version=None,
    app_name=None,
    apache_path=None,
    port=None,
):
    if not project_root:
        project_root = find_1c_project_root()

    autumn = read_1c_json(os.path.join(project_root, "autumn-properties.json"))
    if not autumn:
        autumn = read_1c_json(os.path.join(project_root, "env.json"))
    smoke = read_1c_json(os.path.join(project_root, "tools", "web-test", "smoke.config.json"))

    cfg_v8 = None
    cfg_app = None
    cfg_port = None
    cfg_apache = None
    if autumn and isinstance(autumn.get("vrunner"), dict):
        cfg_v8 = autumn["vrunner"].get("v8version")
    if autumn and isinstance(autumn.get("web"), dict):
        cfg_app = autumn["web"].get("appName")
        cfg_port = autumn["web"].get("port")
        cfg_apache = autumn["web"].get("apachePath")
    if smoke and smoke.get("webUrl"):
        if not cfg_app:
            cfg_app = app_name_from_web_url(smoke["webUrl"])
        if not cfg_port:
            cfg_port = port_from_web_url(smoke["webUrl"])

    if not v8version:
        v8version = cfg_v8
    defaults = platform_apache_defaults(str(v8version) if v8version else "8.3")

    if not apache_path:
        apache_path = cfg_apache or defaults["apache_path"]
    if not os.path.isabs(apache_path):
        apache_path = os.path.abspath(os.path.join(project_root, apache_path))

    if not app_name:
        if cfg_app:
            app_name = cfg_app
        else:
            leaf = os.path.basename(project_root)
            leaf = "".join(ch if (ch.isalnum() or ch in "-_") else "" for ch in leaf)
            if leaf:
                app_name = leaf.lower()
    if app_name:
        app_name = str(app_name).lower()

    if port is not None and int(port) > 0:
        resolved_port = int(port)
    elif cfg_port:
        resolved_port = int(cfg_port)
    else:
        resolved_port = int(defaults["port"])

    return {
        "project_root": project_root,
        "v8version": v8version,
        "app_name": app_name,
        "port": resolved_port,
        "apache_path": apache_path,
        "apache_label": defaults["label"],
        "defaults": defaults,
    }
