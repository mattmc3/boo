#!/bin/sh
# Generates Boo's own lexer and parser with the Boo target, compiles them
# against the Boo companions in src/Boo.Lang.Parser, and checks the result
# tokenises identically to the C# parser the build actually uses.
#
#   $ tools/antlr-boo-target/test/check-boo-parser.sh
#
# Needs java, booc built under src/booc/bin, and Boo.Lang.Parser built under
# src/Boo.Lang.Parser/bin.

set -e

VERSION=4.13.1
PACKAGE=antlr4codegenerator.tool
PACKAGE_VERSION=2.3.0

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
target="$here/../antlr-boo-target.jar"
parser="$root/src/Boo.Lang.Parser"

[ -f "$target" ] || { echo "check: run tools/antlr-boo-target/build.sh first" >&2; exit 1; }

booc=$(find "$root/src/booc/bin" -name booc.dll 2>/dev/null | head -1)
[ -n "$booc" ] || { echo "check: build src/booc first" >&2; exit 1; }

csparser=$(find "$parser/bin" -name Boo.Lang.Parser.dll 2>/dev/null | head -1)
[ -n "$csparser" ] || { echo "check: build src/Boo.Lang.Parser first" >&2; exit 1; }

runtime=$(find "$root" "$HOME/.nuget/packages" -name Antlr4.Runtime.Standard.dll 2>/dev/null | head -1)
[ -n "$runtime" ] || { echo "check: could not find Antlr4.Runtime.Standard.dll" >&2; exit 1; }

jar=$(find "$HOME/.nuget/packages" "$HOME/.cache/NuGetPackages" \
	-name "antlr-$VERSION-complete.jar" 2>/dev/null | head -1)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ -z "$jar" ]; then
	curl -fsSL -o "$work/tool.nupkg" \
		"https://api.nuget.org/v3-flatcontainer/$PACKAGE/$PACKAGE_VERSION/$PACKAGE.$PACKAGE_VERSION.nupkg"
	unzip -q -o "$work/tool.nupkg" -d "$work/tool"
	jar=$(find "$work/tool" -name "antlr-$VERSION-complete.jar" | head -1)
fi

cp "$parser/BooLexer.g4" "$parser/BooParser.g4" "$work/"
cp "$parser/BooLexer.g4.boo" "$parser/BooParser.g4.boo" "$work/"
cp "$parser"/*.boo "$parser"/Util/*.boo "$work/"
cp "$runtime" "$csparser" "$work/"
cp "$(dirname "$booc")/Boo.Lang.dll" "$work/"
compiler=$(find "$root/src/Boo.Lang.Compiler/bin" -name Boo.Lang.Compiler.dll 2>/dev/null | head -1)
[ -n "$compiler" ] || { echo "check: build src/Boo.Lang.Compiler first" >&2; exit 1; }
cp "$compiler" "$work/"

cd "$work"

java -cp "$jar:$target" org.antlr.v4.Tool \
	-Dlanguage=Boo -package Boo.Lang.Parser -visitor -no-listener -o gen \
	BooLexer.g4 BooParser.g4

# BCW0016 fires on the target's fixed import list, which cannot know which
# namespaces a given grammar ends up needing.
dotnet "$booc" -noconfig -target:library -out:BooParser.Boo.dll \
	-r:Antlr4.Runtime.Standard.dll -r:Boo.Lang.Compiler.dll \
	gen/*.boo ./*.boo \
	2>&1 | grep -vE "^Boo Compiler|BCW0016|^[0-9]+ warning" || true

[ -f BooParser.Boo.dll ] || { echo "check: the Boo parser did not compile" >&2; exit 1; }

# The same input through both lexers has to yield the same tokens, channels
# included: the channel is what the skip-whitespace helpers decide.
cat > dump.boo <<'BOO'
import System
import Antlr4.Runtime
import Boo.Lang.Parser
import Boo.Lang.Parser.Util

def Show(s as string) as string:
	return s.Replace("\n", "\\n").Replace("\r", "\\r")

def OnError(recognizer as IRecognizer, offendingSymbol as IToken, filename as string, line as int, charPositionInLine as int, msg as string, e as RecognitionException):
	print "  ${filename} ${line}:${charPositionInLine} ${msg}"

def NewLexer(source as string) as BooLexer:
	lexer = BooLexer(AntlrInputStream(source))
	lexer.TokenFactory = BooToken.CreateTokenFactory(4)
	lexer.RemoveErrorListeners()
	return lexer

lexical = (of string:
	"a = (1, 2)\n",
	"s = \"pre\${1 + 2}post\"\n",
	"t = \"x\$(foo())y\"\n",
	"/* a * b */ c = 1\n",
	"d = 1\r\ne = 2\n",
	"f = [1, 2]  # trailing\n")

# The filter turns indentation into INDENT, DEDENT and EOL, and computes the
# line and column of every token it manufactures.
blocks = (of string:
	"def f():\n\tprint 1\n",
	"class C:\n\tdef m():\n\t\tpass\n",
	"if a:\n\tb()\nelse:\n\tc()\n",
	"def g():\n\tif x:\n\t\ty()\n\tz()\n",
	"a = 1\nend = 2\n")

print "=== tokens ==="
for c in lexical:
	print "--- ${Show(c)}"
	lexer = NewLexer(c)
	token = lexer.NextToken()
	while token.Type != TokenConstants.EOF:
		print "  ${lexer.Vocabulary.GetSymbolicName(token.Type)} ch=${token.Channel} ${Show(token.Text)}"
		token = lexer.NextToken()

print "=== settings ==="
print "  DefaultTabSize ${ParserSettings.DefaultTabSize}"
settings = ParserSettings()
print "  default ${settings.TabSize}"
settings.TabSize = 8
print "  set 8 -> ${settings.TabSize}"
try:
	settings.TabSize = 0
	print "  set 0 -> accepted"
except e as ArgumentOutOfRangeException:
	print "  set 0 -> ${e.GetType().Name}"

print "=== operators ==="
for op in (of string: "<=", ">=", "==", "!=", "=~", "!~"):
	print "  cmp ${op} -> ${OperatorParser.ParseComparison(op)}"
for op in (of string: "=", "|=", "^=", "&=", "<<=", ">>="):
	print "  cond ${op} -> ${OperatorParser.ParseCondAssignment(op)}"
for op in (of string: "=", "+=", "-=", "/=", "*=", "%="):
	print "  assign ${op} -> ${OperatorParser.ParseAssignment(op)}"
try:
	OperatorParser.ParseComparison("??")
	print "  bad operator -> accepted"
except e as ArgumentException:
	print "  bad operator -> ${e.GetType().Name}"

print "=== doc strings ==="
for doc in (of string: "", "one", "\nleading", "trailing\n", "\nboth\n", "\n"):
	print "  ${Show(doc)} -> ${Show(DocStringFormatter.Format(doc))}"

print "=== source locations ==="
locLexer = NewLexer("abc = 1\n")
locToken = locLexer.NextToken()
print "  lexical ${SourceLocationFactory.ToLexicalInfo(locToken)}"
print "  start   ${SourceLocationFactory.ToSourceLocation(locToken)}"
print "  end     ${SourceLocationFactory.ToEndSourceLocation(locToken)}"

print "=== lexer errors ==="
for c in (of string: "a = \"unterminated\n", "b = \u00a1\n"):
	print "--- ${Show(c)}"
	lexer = NewLexer(c)
	lexer.AddErrorListener(BooLexerErrorListener(OnError, "probe.boo"))
	token = lexer.NextToken()
	while token.Type != TokenConstants.EOF:
		token = lexer.NextToken()

print "=== filtered ==="
for c in blocks:
	print "--- ${Show(c)}"
	lexer = NewLexer(c)
	filtered = IndentTokenStreamFilter(lexer, BooLexer.WS, BooLexer.NEWLINE,
		BooLexer.INDENT, BooLexer.DEDENT, BooLexer.EOL, BooLexer.END, BooLexer.ID)
	token = filtered.NextToken()
	while token.Type != TokenConstants.EOF:
		if token.Channel == TokenConstants.DefaultChannel:
			print "  ${lexer.Vocabulary.GetSymbolicName(token.Type)} ${token.Line}:${token.Column} ${Show(token.Text)}"
		token = filtered.NextToken()
BOO

cat > rt.json <<'JSON'
{ "runtimeOptions": { "tfm": "net10.0", "framework": { "name": "Microsoft.NETCore.App", "version": "10.0.0" } } }
JSON

for variant in csharp boo; do
	[ "$variant" = csharp ] && ref=Boo.Lang.Parser.dll || ref=BooParser.Boo.dll
	dotnet "$booc" -noconfig -target:exe -out:"dump-$variant.dll" \
		-r:Antlr4.Runtime.Standard.dll -r:Boo.Lang.Compiler.dll -r:"$ref" dump.boo \
		2>&1 | grep -vE "^Boo Compiler|BCW|^[0-9]+ warning" || true
	# Without this a dumper that fails to build writes the same error on both
	# sides and the comparison passes having compared nothing.
	[ -f "dump-$variant.dll" ] || { echo "check: the $variant dumper did not build" >&2; exit 1; }
	cp rt.json "dump-$variant.runtimeconfig.json"
	dotnet "dump-$variant.dll" > "out-$variant.txt" 2>&1
done

# Every section has to have produced something, for the same reason.
for section in tokens settings operators "doc strings" "source locations" "lexer errors" filtered; do
	grep -q "^=== $section ===" out-csharp.txt \
		|| { echo "check: the $section section produced nothing" >&2; exit 1; }
done
grep -qE "^  cmp <= ->" out-csharp.txt || { echo "check: operators produced no rows" >&2; exit 1; }

# Tokens are only half of it. The two parsers also have to build the same tree,
# which is what reaches the AST builder and everything it calls.
cat > astdump.boo <<'BOO'
import System
import System.IO
import Boo.Lang.Compiler.Ast
import Boo.Lang.Parser

for path in File.ReadAllLines(argv[0]):
	continue if path.Trim().Length == 0
	print "=== ${Path.GetFileName(path)}"
	try:
		cu = BooParser.ParseFile(path)
		for m as Module in cu.Modules:
			print m.ToCodeString()
	except e as Exception:
		print "  <${e.GetType().Name}>"
BOO

ls "$root"/tests/testcases/parser/roundtrip/*.boo > corpus.txt
for variant in csharp boo; do
	[ "$variant" = csharp ] && ref=Boo.Lang.Parser.dll || ref=BooParser.Boo.dll
	dotnet "$booc" -noconfig -target:exe -out:"ast-$variant.dll" \
		-r:Antlr4.Runtime.Standard.dll -r:Boo.Lang.Compiler.dll -r:"$ref" astdump.boo \
		2>&1 | grep -vE "^Boo Compiler|BCW|^[0-9]+ warning" || true
	[ -f "ast-$variant.dll" ] || { echo "check: the $variant AST dumper did not build" >&2; exit 1; }
	cp rt.json "ast-$variant.runtimeconfig.json"
	dotnet "ast-$variant.dll" corpus.txt > "ast-out-$variant.txt" 2>&1
done

corpus=$(grep -c '^=== ' ast-out-csharp.txt)
[ "$corpus" -gt 100 ] || { echo "check: the corpus dump looks empty ($corpus files)" >&2; exit 1; }

if ! diff -u ast-out-csharp.txt ast-out-boo.txt > ast.diff; then
	echo "check-boo-parser: FAILED, the two parsers build different trees" >&2
	head -40 ast.diff >&2
	exit 1
fi

if diff -u out-csharp.txt out-boo.txt > tokens.diff; then
	echo "check-boo-parser: ok ($(grep -c 'ch=' out-csharp.txt) tokens, $(grep -cE '^  [A-Z]+ [0-9]+:' out-csharp.txt) filtered, $(grep -c '^---' out-csharp.txt) inputs, $corpus corpus files)"
else
	echo "check-boo-parser: FAILED, the two lexers disagree" >&2
	head -30 tokens.diff >&2
	exit 1
fi
