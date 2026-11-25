#!/usr/bin/env python3
# web-publish v1.8 — Publish 1C infobase via Apache
# Source: https://github.com/Nikolay-Shirokov/cc-1c-skills

"""
Публикация информационной базы 1С через Apache HTTP Server.
Платформа: V8Path или v8path из .v8-project.json → bin.
AppName: CLI → web.appName из .v8-project.json → smoke.config webUrl → имя папки проекта.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from urllib.parse import urlparse
from xml.sax.saxutils import escape as xml_escape

import psutil


def _find_project_root():
    d = os.getcwd()
    while True:
        if os.path.isfile(os.path.join(d, ".v8-project.json")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.getcwd()
        d = parent


def _read_json(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


def _v8_version_from_path(v8path):
    if not v8path:
        return None
    m = re.search(r"(\d+\.\d+(\.\d+){0,2})", str(v8path))
    return m.group(1) if m else None


def _platform_exe_candidates():
    # Платформа ставится в Program Files или Program Files (x86): берём оба
    # корня из окружения, без литерального пути.
    result = []
    for root in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if root:
            result.extend(glob.glob(os.path.join(root, "1cv8", "*", "bin", "1cv8.exe")))
    return result


def _detected_v8_version_mask():
    candidates = _platform_exe_candidates()
    if not candidates:
        return None
    best = max(candidates, key=lambda p: _version_key(os.path.basename(os.path.dirname(os.path.dirname(p)))))
    return os.path.basename(os.path.dirname(os.path.dirname(best)))


def _version_key(ver_name):
    parts = [int(x) for x in re.findall(r"\d+", ver_name)]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts[:4])


def _find_platform_bin_by_version(version_spec):
    if not version_spec:
        return None
    candidates = _platform_exe_candidates()
    matched = []
    for exe in candidates:
        bin_dir = os.path.dirname(exe)
        ver_dir = os.path.basename(os.path.dirname(bin_dir))
        wsap = os.path.join(bin_dir, "wsap24.dll")
        if not os.path.isfile(wsap):
            continue
        exact = ver_dir == version_spec
        prefix = ver_dir.startswith(version_spec)
        if not exact and not prefix:
            continue
        matched.append((exact, _version_key(ver_dir), ver_dir, bin_dir))
    if not matched:
        return None
    matched.sort(key=lambda t: (t[0], t[1]), reverse=True)
    best = matched[0]
    return {"ver": best[2], "bin": best[3]}


def _platform_apache_defaults(v8version):
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


def _app_name_from_web_url(web_url):
    if not web_url:
        return None
    try:
        path = urlparse(web_url).path or ""
        segs = [s for s in path.split("/") if s]
        return segs[0].lower() if segs else None
    except Exception:
        return None


def _port_from_web_url(web_url):
    if not web_url:
        return None
    try:
        u = urlparse(web_url)
        return u.port
    except Exception:
        return None


def get_our_httpd(httpd_exe_norm):
    """Filter httpd processes by our ApachePath."""
    result = []
    if not httpd_exe_norm:
        return result
    for p in psutil.process_iter(['pid', 'name', 'exe']):
        try:
            if p.info['name'] and 'httpd' in p.info['name'].lower():
                if p.info['exe'] and os.path.normcase(os.path.normpath(p.info['exe'])) == httpd_exe_norm:
                    result.append(p)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return result


def get_all_httpd():
    """Get all httpd processes."""
    result = []
    for p in psutil.process_iter(['pid', 'name', 'exe']):
        try:
            if p.info['name'] and 'httpd' in p.info['name'].lower():
                result.append(p)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return result


def check_port_in_use(port):
    """PID слушающего сокета на порту или None.

    Порт занимает только LISTEN с живым владельцем: TIME_WAIT после закрытых
    сеансов держит запись с pid 0 и занятостью не считается (так же в
    web-publish.ps1).
    """
    for conn in psutil.net_connections(kind='tcp'):
        if conn.laddr and conn.laddr.port == port and conn.status == 'LISTEN':
            if conn.pid and conn.pid > 0:
                return conn.pid
    return None


class PoolInputError(ValueError):
    """Ошибка формата -PoolServices; тексты совпадают с web-publish.ps1."""


def pool_input_items(cli_values, cfg_pool):
    """Элементы пула из -PoolServices или web.poolServices.

    Формат элемента общий с web-publish.ps1: 'Имя=rootUrl', строка делится по
    ',' и ';'. Массив и повтор параметра понимает эта версия; в PowerShell
    повтор запрещён языком, там два сервиса задаются массивом или строкой.
    """
    if cli_values is not None:
        raw = list(cli_values)
    elif isinstance(cfg_pool, str):
        raw = [cfg_pool]
    else:
        raw = [item for item in (cfg_pool or [])]
    items = []
    for item in raw:
        if isinstance(item, str):
            items.extend(re.split(r'[,;]', item))
        else:
            items.append(item)
    return items


def pool_spec(item):
    """(name, rootUrl) элемента пула; PoolInputError на битом входе."""
    if isinstance(item, dict):
        name = str(item.get('name') or '').strip()
        root_url = str(item.get('rootUrl') or '').strip()
        if not name:
            raise PoolInputError("пустой элемент — нужен формат 'Имя=rootUrl'")
        raw = name
    else:
        raw = str(item).strip()
        if not raw:
            raise PoolInputError("пустой элемент — нужен формат 'Имя=rootUrl'")
        if '=' not in raw:
            raise PoolInputError(f"'{raw}': нет '=' — нужен формат 'Имя=rootUrl'")
        name, root_url = (part.strip() for part in raw.split('=', 1))
        if not name:
            raise PoolInputError(f"'{raw}': пустое имя — нужен формат 'Имя=rootUrl'")
    if not root_url:
        raise PoolInputError(f"'{raw}': пустой rootUrl — нужен формат 'Имя=rootUrl'")
    return name, root_url


def pin_apache_root(conf, apache_root):
    """Корень Apache и пути pid/log — внутри своего дерева.

    Копия дерева (web.apachePath на копию) приносит Define SRVROOT исходной
    установки: httpd тогда пишет logs/httpd.pid и logs/error_log в рабочее
    дерево (копия перезаписывала pid живого Apache). Абсолютный PidFile /
    ErrorLog / CustomLog вне дерева переводим в logs/<имя>.
    """
    root_full = os.path.abspath(apache_root)
    root_norm = os.path.normcase(root_full.replace('/', '\\').rstrip('\\'))
    root_fwd = root_full.replace('\\', '/').rstrip('/')
    notes = []

    def _inside(path):
        try:
            p = os.path.normcase(os.path.abspath(path).replace('/', '\\').rstrip('\\'))
        except (OSError, ValueError):
            return False
        return p == root_norm or p.startswith(root_norm + '\\')

    lines = conf.split('\n')

    define_idx = [i for i, l in enumerate(lines) if re.match(r'^[ \t]*Define[ \t]+SRVROOT[ \t]+', l)]
    for i in define_idx:
        indent = re.match(r'^[ \t]*', lines[i]).group(0)
        new_line = f'{indent}Define SRVROOT "{root_fwd}"'
        if lines[i] != new_line:
            lines[i] = new_line
            notes.append(f'Define SRVROOT -> {root_fwd}')

    if not define_idx:
        for i, line in enumerate(lines):
            m = re.match(r'^([ \t]*)ServerRoot[ \t]+(.+)$', line)
            if not m:
                continue
            if '${SRVROOT}' in m.group(2):
                break
            new_line = f'{m.group(1)}ServerRoot "{root_fwd}"'
            if line != new_line:
                lines[i] = new_line
                notes.append(f'ServerRoot -> {root_fwd}')
            break

    directive_re = re.compile(
        r'^([ \t]*)(PidFile|ErrorLog|CustomLog|ScriptLog|RewriteLog)[ \t]+'
        r'(?:"([^"]*)"|(\S+))(.*)$'
    )
    for i, line in enumerate(lines):
        m = directive_re.match(line)
        if not m:
            continue
        indent, directive = m.group(1), m.group(2)
        path = m.group(3) if m.group(3) is not None else m.group(4)
        tail = m.group(5)
        if path.startswith(('syslog:', 'pipe:', '|')):
            continue
        is_abs = bool(re.match(r'^[A-Za-z]:[\\/]', path)) or path.startswith('\\\\') or path.startswith('/')
        candidate = path if is_abs else os.path.join(root_full, path)
        if _inside(candidate):
            continue
        leaf = [s for s in re.split(r'[\\/]', path.rstrip('\\/')) if s]
        leaf = leaf[-1] if leaf else 'httpd.pid'
        lines[i] = f'{indent}{directive} "logs/{leaf}"{tail}'
        notes.append(f'{directive} {path} -> logs/{leaf} (путь вёл вне {root_full})')

    for note in notes:
        print(f'httpd.conf: {note}')
    return '\n'.join(lines)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description='Publish 1C infobase via Apache', allow_abbrev=False)
    parser.add_argument('-V8Path', type=str, default='', help='Path to 1C platform bin directory (for wsap24.dll)')
    parser.add_argument('-V8Version', type=str, default='', help='Platform version mask (from .v8-project.json v8path)')
    parser.add_argument('-InfoBasePath', type=str, default='', help='Path to file infobase')
    parser.add_argument('-InfoBaseServer', type=str, default='', help='1C server (for server infobase)')
    parser.add_argument('-InfoBaseRef', type=str, default='', help='Infobase name on server')
    parser.add_argument('-UserName', type=str, default='', help='1C user name')
    parser.add_argument('-Password', type=str, default='', help='1C password')
    parser.add_argument('-AppName', type=str, default='', help='Publication name (web.appName / smoke webUrl)')
    parser.add_argument('-ApachePath', type=str, default='', help='Apache root (default: %%USERPROFILE%%\\tools\\apache-83|85)')
    parser.add_argument('-Port', type=int, default=None, help='Port (default 8083|8085 by v8version)')
    parser.add_argument('-PoolServices', action='append', default=None,
                        help="HTTP services for session pool: element 'Name=rootUrl', "
                             "items separated by ',' or ';'; repeatable (default web.poolServices)")
    parser.add_argument('-SessionMaxAge', type=int, default=0, help='Pool session idle seconds before replacement (default 20)')
    parser.add_argument('-PoolSize', type=int, default=0, help='Sessions kept in pool (default 4)')
    parser.add_argument('-PoolTimeout', type=int, default=0, help='Seconds to wait for a free pool session (default 5)')
    parser.add_argument('-Manual', action='store_true', help='Do not download Apache — only check and give instructions')
    args = parser.parse_args()

    project_root = _find_project_root()
    registry = _read_json(os.path.join(project_root, ".v8-project.json"))
    smoke = _read_json(os.path.join(project_root, "tools", "web-test", "smoke.config.json"))

    cfg_v8version = None
    cfg_app_name = None
    cfg_port = None
    cfg_apache = None
    web_cfg = {}
    if registry:
        cfg_v8version = _v8_version_from_path(registry.get("v8path"))
        web = registry.get("web")
        if isinstance(web, dict):
            web_cfg = web
            cfg_app_name = web.get("appName")
            cfg_port = web.get("port")
            cfg_apache = web.get("apachePath")
    if not cfg_v8version:
        cfg_v8version = _detected_v8_version_mask()
    if smoke and smoke.get("webUrl"):
        if not cfg_app_name:
            cfg_app_name = _app_name_from_web_url(smoke["webUrl"])
        if not cfg_port:
            cfg_port = _port_from_web_url(smoke["webUrl"])

    # --- Resolve V8Path ---
    v8_path = args.V8Path
    v8_version = args.V8Version or cfg_v8version
    defaults = _platform_apache_defaults(str(v8_version) if v8_version else "8.3")
    if not v8_path:
        if v8_version:
            found = _find_platform_bin_by_version(str(v8_version))
            if found:
                v8_path = found["bin"]
                print(f'Platform by v8version={v8_version} -> {found["ver"]}: {v8_path}')
            else:
                print(
                    f'Error: платформа под v8version={v8_version} не найдена (нужен bin с wsap24.dll). '
                    f'Укажите -V8Path или поправьте v8path в .v8-project.json',
                    file=sys.stderr,
                )
                sys.exit(1)
        else:
            print(
                'Error: не заданы -V8Path и v8path в .v8-project.json',
                file=sys.stderr,
            )
            sys.exit(1)
    elif os.path.isfile(v8_path):
        v8_path = os.path.dirname(v8_path)

    # Validate wsap24.dll
    wsap_dll = os.path.join(v8_path, 'wsap24.dll')
    if not os.path.exists(wsap_dll):
        print(f'Error: wsap24.dll не найден в {v8_path}', file=sys.stderr)
        sys.exit(1)

    # --- Validate connection ---
    if not args.InfoBasePath and (not args.InfoBaseServer or not args.InfoBaseRef):
        print('Error: укажите -InfoBasePath или -InfoBaseServer + -InfoBaseRef', file=sys.stderr)
        sys.exit(1)

    # --- Resolve ApachePath (profile, not project) ---
    apache_path = args.ApachePath or cfg_apache or defaults["apache_path"]
    if not os.path.isabs(apache_path):
        apache_path = os.path.abspath(os.path.join(project_root, apache_path))
    print(f'Apache profile: apache-{defaults["label"]} -> {apache_path}')

    port = args.Port
    if port is None:
        port = int(cfg_port) if cfg_port else int(defaults["port"])

    # --- HTTP-service session pool: единый вход -PoolServices (как в web-publish.ps1) ---
    cfg_pool = web_cfg.get("poolServices") or []
    pool_items = pool_input_items(args.PoolServices, cfg_pool)
    pool_services = []
    for item in pool_items:
        try:
            pool_services.append(pool_spec(item))
        except PoolInputError as exc:
            print(f'Error: PoolServices: {exc}', file=sys.stderr)
            sys.exit(1)
    session_max_age = args.SessionMaxAge or int(web_cfg.get("poolSessionMaxAge") or 20)
    pool_size = args.PoolSize or int(web_cfg.get("poolSize") or 4)
    pool_timeout = args.PoolTimeout or int(web_cfg.get("poolTimeout") or 5)

    # --- Check / Install Apache ---
    httpd_exe = os.path.join(apache_path, 'bin', 'httpd.exe')

    if not os.path.exists(httpd_exe):
        if args.Manual:
            print(f'Apache не найден: {apache_path}')
            print('')
            print('Установите Apache вручную:')
            print('  1. Скачайте Apache Lounge (x64) с https://www.apachelounge.com/download/')
            print(f'  2. Распакуйте содержимое Apache24\\ в: {apache_path}')
            print('  3. Запустите скрипт повторно')
            sys.exit(1)

        print('Apache не найден. Скачиваю...')
        tmp_zip = os.path.join(tempfile.gettempdir(), 'apache24.zip')
        tmp_dir = os.path.join(tempfile.gettempdir(), 'apache24_extract')

        try:
            # Parse Apache Lounge download page for latest Win64 zip URL
            download_page = 'https://www.apachelounge.com/download/'
            print(f'Определяю актуальную версию с {download_page} ...')
            req = urllib.request.Request(download_page, headers={
                'User-Agent': 'Mozilla/5.0',
            })
            with urllib.request.urlopen(req, timeout=30) as resp:
                html = resp.read().decode('utf-8', errors='replace')

            # Links are typically relative (/download/...), try that first
            m = re.search(r'(?i)href="(/download/[^"]*?httpd-[^"]*?Win64[^"]*?\.zip)"', html)
            if not m:
                m = re.search(r'(?i)href="(https://[^"]*?httpd-[^"]*?Win64[^"]*?\.zip)"', html)

            if m:
                zip_url = m.group(1)
                if zip_url.startswith('/'):
                    zip_url = f'https://www.apachelounge.com{zip_url}'
                print(f'Найдено: {zip_url}')
            else:
                print('Не удалось определить ссылку автоматически.', file=sys.stderr)
                print(f'Скачайте вручную: {download_page}')
                sys.exit(1)

            urllib.request.urlretrieve(zip_url, tmp_zip)
        except SystemExit:
            raise
        except Exception as e:
            print(f'Error: не удалось скачать Apache: {e}', file=sys.stderr)
            print('Скачайте вручную: https://www.apachelounge.com/download/')
            sys.exit(1)

        print('Распаковка...')
        if os.path.exists(tmp_dir):
            shutil.rmtree(tmp_dir, ignore_errors=True)

        with zipfile.ZipFile(tmp_zip, 'r') as zf:
            zf.extractall(tmp_dir)

        # Move Apache24 contents up to ApachePath
        inner_dir = os.path.join(tmp_dir, 'Apache24')
        if not os.path.isdir(inner_dir):
            # Try to find Apache24 in nested folder
            found_inner = None
            for root, dirs, files in os.walk(tmp_dir):
                if 'Apache24' in dirs:
                    found_inner = os.path.join(root, 'Apache24')
                    break
            if found_inner:
                inner_dir = found_inner
            else:
                print('Error: каталог Apache24 не найден в архиве', file=sys.stderr)
                sys.exit(1)

        os.makedirs(apache_path, exist_ok=True)
        # Copy contents of inner_dir to apache_path
        for item in os.listdir(inner_dir):
            src = os.path.join(inner_dir, item)
            dst = os.path.join(apache_path, item)
            if os.path.isdir(src):
                if os.path.exists(dst):
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)

        # Cleanup
        try:
            os.remove(tmp_zip)
        except OSError:
            pass
        try:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        except OSError:
            pass

        # ServerRoot привязывается ниже, в общем шаге pin_apache_root:
        # одно поведение и для свежей установки, и для копии дерева.

        print(f'Apache установлен: {apache_path}')

    # --- Derive AppName ---
    app_name = (args.AppName or "").strip()
    if not app_name and cfg_app_name:
        app_name = str(cfg_app_name)
        print(f"AppName from project config: {app_name}")
    if not app_name:
        leaf = re.sub(r"[^\w\-]", "", os.path.basename(project_root))
        if leaf:
            app_name = leaf.lower()
            print(
                f"AppName from project folder: {app_name} "
                f"(задайте web.appName в .v8-project.json или webUrl в smoke.config)"
            )
    app_name = app_name.lower()

    if not app_name:
        print(
            "Error: не удалось определить имя публикации. "
            "Задайте -AppName или web.appName в .v8-project.json / smoke.config webUrl",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Публикация: {app_name} (port {port})")

    # --- Create publish directory ---
    publish_dir = os.path.join(apache_path, 'publish', app_name)
    os.makedirs(publish_dir, exist_ok=True)

    # --- Generate default.vrd ---
    vrd_path = os.path.join(publish_dir, 'default.vrd')

    ib_parts = []
    if args.InfoBaseServer and args.InfoBaseRef:
        ib_parts.append(f'Srvr=&quot;{args.InfoBaseServer}&quot;')
        ib_parts.append(f'Ref=&quot;{args.InfoBaseRef}&quot;')
    else:
        ib_parts.append(f'File=&quot;{args.InfoBasePath}&quot;')
    if args.UserName:
        ib_parts.append(f'Usr=&quot;{args.UserName}&quot;')
    if args.Password:
        ib_parts.append(f'Pwd=&quot;{args.Password}&quot;')
    ib_string = ';'.join(ib_parts) + ';'

    # Пул сеансов задаётся на элементе <service>: на <httpServices> платформа 8.5
    # эти атрибуты не принимает. publishByDefault остаётся true — новые сервисы
    # (в том числе из расширений) публикуются как раньше.
    xml_attr = {'"': '&quot;', "'": '&apos;'}

    def _pool_line(name, root_url):
        attrs = f'name="{xml_escape(name, xml_attr)}"'
        if root_url:
            attrs += f' rootUrl="{xml_escape(root_url, xml_attr)}"'
        return (
            f'        <service {attrs} enable="true" reuseSessions="autouse" '
            f'sessionMaxAge="{session_max_age}" poolSize="{pool_size}" poolTimeout="{pool_timeout}"/>'
        )

    pool_service_lines = [_pool_line(name, root_url) for name, root_url in pool_services]
    if pool_service_lines:
        http_services_xml = (
            '    <httpServices publishByDefault="true" publishExtensionsByDefault="true">\n'
            + '\n'.join(pool_service_lines)
            + '\n    </httpServices>'
        )
    else:
        http_services_xml = '    <httpServices publishByDefault="true" publishExtensionsByDefault="true"/>'

    vrd_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<point xmlns="http://v8.1c.ru/8.2/virtual-resource-system"
       xmlns:xs="http://www.w3.org/2001/XMLSchema"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       base="/{app_name}"
       ib="{ib_string}">
    <standardOdata enable="true"/>
    <ws pointEnableCommon="true"/>
{http_services_xml}
</point>'''

    with open(vrd_path, 'wb') as f:
        f.write(b'\xef\xbb\xbf')
        f.write(vrd_content.encode('utf-8'))
    print(f'default.vrd: {vrd_path}')
    if pool_services:
        names = ', '.join(f"{name}={root_url}" if root_url else name for name, root_url in pool_services)
        print(
            f"Пул сеансов HTTP-сервисов: {names} "
            f"(sessionMaxAge={session_max_age}, poolSize={pool_size}, poolTimeout={pool_timeout})"
        )
    else:
        print('Пул сеансов HTTP-сервисов: выключен (web.poolServices / -PoolServices пуст)')

    # --- Update httpd.conf ---
    conf_file = os.path.join(apache_path, 'conf', 'httpd.conf')
    if not os.path.exists(conf_file):
        print(f'Error: httpd.conf не найден: {conf_file}', file=sys.stderr)
        sys.exit(1)

    with open(conf_file, 'r', encoding='utf-8-sig') as f:
        conf_content = f.read()

    conf_content = pin_apache_root(conf_content, apache_path)

    apache_path_fwd = apache_path.replace('\\', '/')
    wsap_dll_fwd = wsap_dll.replace('\\', '/')
    publish_dir_fwd = publish_dir.replace('\\', '/')
    vrd_path_fwd = vrd_path.replace('\\', '/')

    # --- Global block (Listen + LoadModule) ---
    global_marker_start = '# --- 1C: global ---'
    global_marker_end = '# --- End: global ---'
    global_block = (
        f'{global_marker_start}\n'
        f'Listen {port}\n'
        f'LoadModule _1cws_module "{wsap_dll_fwd}"\n'
        f'{global_marker_end}'
    )

    if re.search(re.escape(global_marker_start), conf_content):
        # Replace existing global block
        pattern = re.escape(global_marker_start) + r'[\s\S]*?' + re.escape(global_marker_end)
        conf_content = re.sub(pattern, global_block, conf_content)
    else:
        # Comment out default Listen to avoid port conflict
        conf_content = re.sub(r'(?m)^(Listen\s+\d+)', r'#\1  # commented by web-publish', conf_content)
        # Append global block
        conf_content = conf_content.rstrip() + '\n\n' + global_block + '\n'

    # --- Publication block ---
    pub_marker_start = f'# --- 1C Publication: {app_name} ---'
    pub_marker_end = f'# --- End: {app_name} ---'
    pub_block = (
        f'{pub_marker_start}\n'
        f'Alias "/{app_name}" "{publish_dir_fwd}"\n'
        f'<Directory "{publish_dir_fwd}">\n'
        f'    AllowOverride All\n'
        f'    Require all granted\n'
        f'    SetHandler 1c-application\n'
        f'    ManagedApplicationDescriptor "{vrd_path_fwd}"\n'
        f'</Directory>\n'
        f'{pub_marker_end}'
    )

    if re.search(re.escape(pub_marker_start), conf_content):
        # Replace existing publication block
        pattern = re.escape(pub_marker_start) + r'[\s\S]*?' + re.escape(pub_marker_end)
        conf_content = re.sub(pattern, pub_block, conf_content)
    else:
        # Append publication block
        conf_content = conf_content.rstrip() + '\n\n' + pub_block + '\n'

    with open(conf_file, 'w', encoding='utf-8') as f:
        f.write(conf_content)
    print('httpd.conf обновлён')

    # --- Ensure logs dir: pid и error_log пишутся в своё дерево ---
    os.makedirs(os.path.join(apache_path, 'logs'), exist_ok=True)

    # --- Normalize httpd_exe for process matching ---
    if os.path.exists(httpd_exe):
        httpd_exe_norm = os.path.normcase(os.path.normpath(os.path.realpath(httpd_exe)))
    else:
        httpd_exe_norm = os.path.normcase(os.path.normpath(httpd_exe))

    # --- Check port availability ---
    holder_pid = check_port_in_use(port)
    if holder_pid:
        our_proc = get_our_httpd(httpd_exe_norm)
        if not our_proc:
            # Port is held by someone else
            try:
                holder_proc = psutil.Process(holder_pid)
                # Имя без .exe — как ProcessName в web-publish.ps1.
                holder_name = f'{os.path.splitext(holder_proc.name())[0]} (PID: {holder_pid})'
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                holder_name = f'PID {holder_pid}'
            print(f'Error: порт {port} занят процессом {holder_name}', file=sys.stderr)
            print('Укажите другой порт: -Port 9090')
            sys.exit(1)

    # --- Start Apache if not running ---
    httpd_proc = get_our_httpd(httpd_exe_norm)
    if httpd_proc:
        first_pid = httpd_proc[0].pid
        print(f'Apache уже запущен (PID: {first_pid})')
        print('Перезапуск для применения конфигурации...')
        for p in httpd_proc:
            try:
                p.kill()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        time.sleep(1)
    else:
        # Check if a foreign httpd holds the port
        foreign_httpd = get_all_httpd()
        if foreign_httpd:
            print(f'[WARN] Обнаружен сторонний Apache (PID: {foreign_httpd[0].pid})')
            print(f'       Наш Apache: {httpd_exe}')

    print('Запуск Apache...')
    subprocess.Popen(
        [httpd_exe],
        cwd=apache_path,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )

    time.sleep(2)

    httpd_check = get_our_httpd(httpd_exe_norm)
    if httpd_check:
        print(f'Apache запущен (PID: {httpd_check[0].pid})')
    else:
        print('Apache не удалось запустить', file=sys.stderr)
        # Run config test for diagnostics
        try:
            result = subprocess.run(
                [httpd_exe, '-t'],
                capture_output=True,
                text=True,
                timeout=10,
            )
            test_output = (result.stdout + result.stderr).strip()
            if test_output:
                print('--- httpd -t ---')
                for line in test_output.splitlines():
                    print(f'  {line}')
        except Exception:
            pass
        error_log = os.path.join(apache_path, 'logs', 'error.log')
        if os.path.exists(error_log):
            print('--- error.log (последние 10 строк) ---')
            try:
                with open(error_log, 'r', encoding='utf-8-sig', errors='replace') as f:
                    all_lines = f.readlines()
                for line in all_lines[-10:]:
                    print(line.rstrip())
            except Exception:
                pass
        sys.exit(1)

    # --- Result ---
    print('')
    print('=== Публикация готова ===')
    print(f'URL (веб-клиент): http://localhost:{port}/{app_name}/ru_RU/')
    print(f'OData:            http://localhost:{port}/{app_name}/odata/standard.odata')
    print(f'HTTP-сервисы:     http://localhost:{port}/{app_name}/hs/<RootUrl>/...')
    print(f'Web-сервисы:      http://localhost:{port}/{app_name}/ws/<Имя>?wsdl')


if __name__ == '__main__':
    main()
