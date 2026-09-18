{
	"mcpServers": {
		"vrunner": {
			"command": "{{VRUNNER_MCP_BAT}}"
		},
		"1c-mcp-toolkit": {
			"url": "http://127.0.0.1:6003/mcp",
			"type": "streamable-http"
		},
		"1c-ninja-mcp": {
			"command": "oscript",
			"args": ["{{AUTUMN_MAIN}}"],
			"env": {
				"SHCNTX_HELP_DB": "{{SHCNTX_HELP_DB}}",
				"NINJA_URL": "http://localhost:{{WEB_PORT}}/{{APP_NAME}}/hs/ninja-live",
				"NINJA_USER": "{{BSL_USER}}",
				"NINJA_PASSWORD": "{{BSL_PASSWORD}}"
			}
		},
		"bsl-analyzer-reference": {
			"command": "{{BSL_ANALYZER_EXE}}",
			"args": [
				"mcp",
				"serve",
				"--profile",
				"reference"
			]
		},
		"bsl-analyzer-workspace": {
			"command": "{{BSL_ANALYZER_EXE}}",
			"args": [
				"mcp",
				"serve",
				"--profile",
				"workspace",
				"--source-dir",
				"{{PROJECT_ROOT}}"
			]
		}
	}
}
