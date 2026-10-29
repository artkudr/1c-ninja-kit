#!/usr/bin/env python3
# Shared resolver: profile Apache by platform line (8.3 / 8.5).
# Import from web-* scripts. No Apache inside projects.
#
# Profile roots:
#   %USERPROFILE%\tools\apache-83  → port 8083  (платформа 8.3*)
#   %USERPROFILE%\tools\apache-85  → port 8085  (платформа 8.5*)
#
# Workspace overrides (.v8-project.json):
#   v8path (версия платформы), web.appName, web.port, web.apachePath

import json
import os
import re
import glob
from urllib.parse import urlparse


def find_1c_project_root(start_dir=None):
    d = os.path.abspath(start_dir or os.getcwd())
    while True:
        if os.path.isfile(os.path.join(d, ".v8-project.json")):
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


def v8_version_from_path(v8path):
    if not v8path:
        return None
    m = re.search(r"(\d+\.\d+(\.\d+){0,2})", str(v8path))
    return m.group(1) if m else None


def detected_v8_version_mask():
    candidates = []
    for pattern in (
        r"C:\Program Files\1cv8\*\bin\1cv8.exe",
        r"C:\Program Files (x86)\1cv8\*\bin\1cv8.exe",
    ):
        candidates.extend(glob.glob(pattern))
    if not candidates:
        return None

    def ver_key(p):
        name = os.path.basename(os.path.dirname(os.path.dirname(p)))
        try:
            return tuple(int(x) for x in name.split("."))
        except Exception:
            return (0,)

    best = max(candidates, key=ver_key)
    return os.path.basename(os.path.dirname(os.path.dirname(best)))


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

    registry = read_1c_json(os.path.join(project_root, ".v8-project.json"))
    smoke = read_1c_json(os.path.join(project_root, "tools", "web-test", "smoke.config.json"))

    cfg_v8 = None
    cfg_app = None
    cfg_port = None
    cfg_apache = None
    if registry:
        cfg_v8 = v8_version_from_path(registry.get("v8path"))
        web = registry.get("web")
        if isinstance(web, dict):
            cfg_app = web.get("appName")
            cfg_port = web.get("port")
            cfg_apache = web.get("apachePath")
    if not cfg_v8:
        cfg_v8 = detected_v8_version_mask()
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
