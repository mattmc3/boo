#!/bin/sh
# Checks the two things astgen's Boo output has to get right:
#
#   1. the C# it generates is byte for byte what is committed, so retargeting
#      has not disturbed the language the build actually uses
#   2. the Boo it generates compiles, and its enums carry the same members and
#      the same values as the C# ones
#
#   $ scripts/check-astgen-boo.sh
#
# Needs booi, booc and Boo.Lang.Compiler built under src/*/bin. Run from
# anywhere; astgen itself reads paths relative to the repository root.

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

booi=$(find "$root/src/booi/bin" -name booi.dll 2>/dev/null | head -1)
booc=$(find "$root/src/booc/bin" -name booc.dll 2>/dev/null | head -1)
compiler=$(find "$root/src/Boo.Lang.Compiler/bin" -name Boo.Lang.Compiler.dll 2>/dev/null | head -1)
[ -n "$booi" ] || { echo "check-astgen: build src/booi first" >&2; exit 1; }
[ -n "$booc" ] || { echo "check-astgen: build src/booc first" >&2; exit 1; }
[ -n "$compiler" ] || { echo "check-astgen: build src/Boo.Lang.Compiler first" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$root"

# 1. The C# has to come back identical. applyTemplate skips a file that already
# exists unless it overwrites, so this runs against a copy rather than an empty
# directory.
cp -R src/Boo.Lang.Compiler/Ast "$work/csharp"
dotnet "$booi" scripts/astgen.boo --out="$work/csharp" >/dev/null
if ! diff -rq src/Boo.Lang.Compiler/Ast "$work/csharp" >"$work/csharp.diff" 2>&1; then
	echo "check-astgen: FAILED, the C# output changed" >&2
	head -20 "$work/csharp.diff" >&2
	exit 1
fi

# 2. The Boo has to compile.
mkdir -p "$work/boo"
dotnet "$booi" scripts/astgen.boo --language=boo --out="$work/boo" >/dev/null

cp "$(dirname "$booc")/Boo.Lang.dll" "$work/boo/"
cd "$work/boo"
dotnet "$booc" -noconfig -target:library -out:AstEnums.dll ./*.Generated.boo \
	2>&1 | grep -vE "^Boo Compiler|^[0-9]+ warning" || true
[ -f AstEnums.dll ] || { echo "check-astgen: the generated Boo did not compile" >&2; exit 1; }

# 3. Same members, same values. A flags enum takes its value from an
# initializer expression, so this covers more than the member names.
cat > dumpenums.boo <<'BOO'
import System
import System.IO
import System.Collections.Generic
import System.Reflection

asm = Assembly.LoadFrom(Path.GetFullPath(argv[0]))
only = List[of string](argv[1].Split(char(',')))

names = List[of string]()
for t as Type in asm.GetTypes():
	continue unless t.IsEnum and t.Namespace == "Boo.Lang.Compiler.Ast"
	names.Add(t.Name) if only.Contains(t.Name)
names.Sort()

for n in names:
	t = asm.GetType("Boo.Lang.Compiler.Ast." + n)
	print n
	for field in Enum.GetNames(t):
		print "  ${field} = ${Convert.ToInt64(Enum.Parse(t, field))}"
BOO

cat > rt.json <<'JSON'
{ "runtimeOptions": { "tfm": "net10.0", "framework": { "name": "Microsoft.NETCore.App", "version": "10.0.0" } } }
JSON

dotnet "$booc" -noconfig -target:exe -out:dumpenums.dll dumpenums.boo >/dev/null 2>&1
cp rt.json dumpenums.runtimeconfig.json

list=$(ls ./*.Generated.boo | sed 's|.*/||; s|\.Generated\.boo||' | paste -sd, -)
dotnet dumpenums.dll "$compiler" "$list" > out-csharp.txt 2>&1
dotnet dumpenums.dll AstEnums.dll "$list" > out-boo.txt 2>&1

if diff -u out-csharp.txt out-boo.txt > enums.diff; then
	echo "check-astgen: ok ($(grep -c ' = ' out-csharp.txt) members, $(grep -cv ' = ' out-csharp.txt) enums)"
else
	echo "check-astgen: FAILED, the enums differ" >&2
	head -30 enums.diff >&2
	exit 1
fi
