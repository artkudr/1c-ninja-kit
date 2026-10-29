# Конфиг bsl-analyzer для проекта.
# Управляет LSP / CLI analyze / MCP diagnostics.
# Пилот: шумные style-правила выключены; семантика (unused, unreachable и т.п.) остаётся.

[source]
root = "src/cf"
# Все CFE из выгрузки (имя = имя каталога)
extensions = ["src/cfe/*"]
# EPF/ERF (bsl-analyzer ≥0.2.77): без ключа — auto-discovery src/epf/*, src/erf/*.
# Канон nested: src/epf/<Name>/<Name>.xml + src/epf/<Name>/<Name>/ (то же для erf).
# Явный список — только если нужен depends_on / нестандартный путь:
# externals = [
#   { name = "МояОбработка", path = "src/epf/МояОбработка", depends_on = [] },
# ]
# externals = []  # явно выключить внешние

[diagnostics]
ordinaryAppSupport = false
dataflowMaxIterations = 10000

[diagnostics.parameters]
# Шум на типовой УТ / больших модулях — выключено для пилота
CommentedCode = false
Typo = false
MagicNumber = false
MagicDate = false
ConsecutiveEmptyLines = false
SpaceAtStartComment = false
YoLetterUsage = false
LatinAndCyrillicSymbolsInWord = false
UsingHardcodeNetworkAccess = false
UsingHardcodePath = false
UsingHardcodeSecretInformation = false
MissingSpace = false
UsingThisForm = false
ExcessiveAutoTestCheck = false
CanonicalSpellingKeywords = false
DuplicateStringLiteral = false
SemicolonPresence = false

# Пороги ослаблены (типовой код иначе тонет в замечаниях)
LineLength = { maxLineLength = 200 }
MethodSize = { maxMethodSize = 400 }
CyclomaticComplexity = { complexityThreshold = 50 }
CognitiveComplexity = { complexityThreshold = 40 }
NestedStatements = { maxAllowedLevel = 6 }
NumberOfParams = { maxParamsCount = 12 }
NumberOfOptionalParams = { maxOptionalParamsCount = 8 }
TooManyReturns = { maxReturnsCount = 8 }
IfConditionComplexity = { maxIfConditionComplexity = 6 }
