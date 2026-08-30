#!/bin/sh
# Generates a parser for Calc.g4 with the Boo target, compiles it with booc -wsa
# and runs driver.boo over it. Prints the expected output on success.
#
#   $ tools/antlr-boo-target/test/check.sh
#
# Needs java, and booc built under src/booc/bin.

set -e

VERSION=4.13.1
PACKAGE=antlr4codegenerator.tool
PACKAGE_VERSION=2.3.0

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
target="$here/../antlr-boo-target.jar"

[ -f "$target" ] || { echo "check: run tools/antlr-boo-target/build.sh first" >&2; exit 1; }

booc=$(find "$root/src/booc/bin" -name booc.dll 2>/dev/null | head -1)
[ -n "$booc" ] || { echo "check: build src/booc first" >&2; exit 1; }

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

cp "$here/Calc.g4" "$here/driver.boo" "$work/"
cp "$runtime" "$work/"
cp "$(dirname "$booc")/Boo.Lang.dll" "$work/"

cd "$work"
java -cp "$jar:$target" org.antlr.v4.Tool \
	-Dlanguage=Boo -package Toy -visitor -no-listener -o gen Calc.g4

dotnet "$booc" -noconfig -target:exe -out:calc.dll \
	-r:Antlr4.Runtime.Standard.dll gen/*.boo driver.boo

cat > calc.runtimeconfig.json <<'JSON'
{ "runtimeOptions": { "tfm": "net10.0", "framework": { "name": "Microsoft.NETCore.App", "version": "10.0.0" } } }
JSON

actual=$(dotnet calc.dll)
expected='errors: 0
7
9
9'

if [ "$actual" = "$expected" ]; then
	echo "check: ok"
else
	echo "check: FAILED" >&2
	echo "expected:" >&2; echo "$expected" >&2
	echo "actual:" >&2; echo "$actual" >&2
	exit 1
fi
