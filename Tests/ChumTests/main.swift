import Foundation

let runner = TestRunner()

LayoutEngineTests.runAll(runner)
WindowCommandCodableTests.runAll(runner)
URLParsingTests.runAll(runner)
FuzzyMatchTests.runAll(runner)
HotkeyDisplayTests.runAll(runner)
VersionCompareTests.runAll(runner)
AppShortcutCodableTests.runAll(runner)
SnippetCodableTests.runAll(runner)
NoteCodableTests.runAll(runner)
ChatModelTests.runAll(runner)
ChatMarkdownTests.runAll(runner)
TextTransformTests.runAll(runner)
SnippetTemplateTests.runAll(runner)
CalculatorTests.runAll(runner)
SavedColorTests.runAll(runner)

print()
print(runner.summary)
exit(runner.exitCode)
