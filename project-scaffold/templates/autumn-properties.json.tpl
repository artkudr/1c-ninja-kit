{
	"vrunner": {
		"ibconnection": "{{IBCONNECTION}}",
		"db-user": "{{DB_USER}}",
		"db-pwd": "{{DB_PWD}}",
		"root": ".",
		"workspace": ".",
		"v8version": "{{V8VERSION}}",
		"locale": "ru",
		"language": "ru",
		"additional": "/DisplayAllFunctions /L ru",
		"ordinaryapp": "-1",
		"validate": {
			"syntax-check": {
				"groupbymetadata": true,
				"exception-file": "tools/syntax-check-excludes.txt",
				"junitpath": "build/out/syntax-check/junit/junit.xml",
				"allure-results2": "build/out/syntax-check/allure",
				"mode": [
					"ExtendedModulesCheck",
					"ThinClient",
					"WebClient",
					"Server",
					"ExternalConnection",
					"ThickClientOrdinaryApplication"
				]
			}
		}
	},
	"web": {
		"appName": "{{APP_NAME}}",
		"port": {{WEB_PORT}}
	}
}
