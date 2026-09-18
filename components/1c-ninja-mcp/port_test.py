# Smoke-тест 1c-ninja-mcp: static-инструменты + опционально live.
# Фикстуры static: qbikdev (выгрузка src/cf).
# Live: если задан NINJA_URL (fallback BSL_ANALYZER_URL) — live_version и live_query.
# Запуск: python port_test.py
import asyncio
import os

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = r"C:\1C\projects\1c-ninja-mcp"
SERVER = os.path.join(ROOT, "main.os")
HELP_DB = os.path.join(ROOT, "src", "data", "shcntx_help.db")
CF = r"C:\1C\projects\qbikdev\src\cf"
SMALL_BSL_DIR = os.path.join(CF, "AccountingRegisters", "Управленческий")
SMALL_BSL = os.path.join(SMALL_BSL_DIR, "Ext", "ManagerModule.bsl")
XML_DIR = os.path.join(CF, "AccountingRegisters")

EXPECTED_MIN_TOOLS = 17  # 5 static + 10 live + epf_decompile + cf_dump_xml


def txt(r):
    return "".join(c.text if hasattr(c, "text") else str(c) for c in r.content)


async def main():
    env = {
        **os.environ,
        "SHCNTX_HELP_DB": HELP_DB,
    }
    # Не затираем NINJA_* / BSL_ANALYZER_* из окружения вызывающего процесса, если уже заданы.
    params = StdioServerParameters(
        command="oscript",
        args=[SERVER],
        cwd=ROOT,
        env=env,
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            print("serverInfo:", init.serverInfo.name, init.serverInfo.version)
            print("protocolVersion:", init.protocolVersion)

            tools = (await session.list_tools()).tools
            names = sorted(t.name for t in tools)
            print(f"\ntools/list -> {len(tools)} tools:")
            for t in tools:
                props = t.inputSchema.get("properties", {})
                print(f"  - {t.name}: params {list(props.keys())} | required {t.inputSchema.get('required', [])}")
            assert len(tools) >= EXPECTED_MIN_TOOLS, f"expected >= {EXPECTED_MIN_TOOLS} tools, got {len(tools)}: {names}"
            for required in (
                "bsl_search",
                "xml_search",
                "config_list",
                "read_module",
                "syntax_help_search",
                "live_version",
                "live_query",
                "live_validate_query",
                "live_check_syntax",
                "live_metadata_list",
                "live_metadata_structure",
                "live_event_log",
                "live_execute",
                "live_eval",
            ):
                assert required in names, f"missing tool: {required}"

            r = await session.call_tool("bsl_search", {"path": SMALL_BSL_DIR, "query": "Процедура"})
            lines = txt(r).splitlines()
            print(f"\n== bsl_search('Процедура'): hits = {len(lines)}, isError = {r.isError}")
            for l in lines[:3]:
                print("   ", l[:140])
            assert not r.isError and len(lines) > 0

            r = await session.call_tool(
                "bsl_search",
                {"path": SMALL_BSL_DIR, "query": r"Процедура|Функция", "useRegex": True},
            )
            print(f"== bsl_search(regex): hits = {len(txt(r).splitlines())}, isError = {r.isError}")
            assert not r.isError

            r = await session.call_tool("xml_search", {"path": XML_DIR, "query": "uuid="})
            lines = txt(r).splitlines()
            print(f"\n== xml_search('uuid='): hits = {len(lines)}, isError = {r.isError}")
            for l in lines[:3]:
                print("   ", l[:140])
            assert not r.isError and len(lines) > 0

            r = await session.call_tool("config_list", {"path": SMALL_BSL_DIR, "maxDepth": 1})
            print(f"\n== config_list(maxDepth=1): isError = {r.isError}")
            print("   ", txt(r)[:300].replace("\n", "\n    "))
            assert not r.isError

            r = await session.call_tool("read_module", {"path": SMALL_BSL})
            print(f"\n== read_module(whole): isError = {r.isError}, строк = {len(txt(r).splitlines())}")
            assert not r.isError

            r = await session.call_tool("read_module", {"path": SMALL_BSL, "method": "*"})
            print(f"== read_module(method='*'): isError = {r.isError}")
            print("   ", txt(r)[:300].replace("\n", "\n    "))
            assert not r.isError

            decls = txt(r)
            method_name = None
            for line in decls.splitlines():
                if "Процедура " in line or "Функция " in line:
                    part = line.strip().split()
                    if len(part) >= 2:
                        method_name = part[1]
                        break
            if method_name:
                r = await session.call_tool("read_module", {"path": SMALL_BSL, "method": method_name})
                print(f"== read_module(method='{method_name}'): строк = {len(txt(r).splitlines())}, isError = {r.isError}")
                assert not r.isError

            r = await session.call_tool(
                "syntax_help_search",
                {"query": "Массив", "dbPath": HELP_DB, "limit": 5, "snippet_length": 120},
            )
            print(f"\n== syntax_help_search('Массив'): isError = {r.isError}")
            print("   ", txt(r)[:400].replace("\n", "\n    "))
            assert not r.isError

            print("\nOK: all static tools responded")

            live_url = os.environ.get("NINJA_URL", "").strip() or os.environ.get("BSL_ANALYZER_URL", "").strip()
            if not live_url:
                print("\nSKIP live: NINJA_URL not set")
                return

            print(f"\n== live against {live_url}")
            r = await session.call_tool("live_version", {})
            body = txt(r)
            print(f"live_version: isError = {r.isError}, body = {body[:200]}")
            assert not r.isError, body
            assert "version" in body

            r = await session.call_tool(
                "live_query",
                {"query": "ВЫБРАТЬ 1 КАК Число", "limit": 1},
            )
            body = txt(r)
            print(f"live_query: isError = {r.isError}, body = {body[:300]}")
            assert not r.isError, body
            assert "columns" in body or "Число" in body

            print("\nOK: live_version + live_query responded")


if __name__ == "__main__":
    asyncio.run(main())
