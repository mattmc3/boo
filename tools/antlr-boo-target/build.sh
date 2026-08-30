#!/bin/sh
# Builds antlr-boo-target.jar, the Boo code generation target for ANTLR 4.
#
# The jar is committed, so this only needs running after editing BooTarget.java
# or Boo.stg. It needs a JDK; using the jar afterwards needs only java, which is
# what scripts/regenerate-parser.sh already asks for.
#
#   $ tools/antlr-boo-target/build.sh

set -e

VERSION=4.13.1
PACKAGE=antlr4codegenerator.tool
PACKAGE_VERSION=2.3.0

here=$(cd "$(dirname "$0")" && pwd)

if ! command -v javac >/dev/null 2>&1; then
	echo "build: javac is needed to compile BooTarget.java, and is not on PATH." >&2
	exit 1
fi

jar=$(find "$HOME/.nuget/packages" "$HOME/.cache/NuGetPackages" \
	-name "antlr-$VERSION-complete.jar" 2>/dev/null | head -1)

if [ -z "$jar" ]; then
	echo "build: fetching the ANTLR $VERSION tool"
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT
	curl -fsSL -o "$work/tool.nupkg" \
		"https://api.nuget.org/v3-flatcontainer/$PACKAGE/$PACKAGE_VERSION/$PACKAGE.$PACKAGE_VERSION.nupkg"
	unzip -q -o "$work/tool.nupkg" -d "$work"
	jar=$(find "$work" -name "antlr-$VERSION-complete.jar" | head -1)
fi

if [ -z "$jar" ]; then
	echo "build: could not find antlr-$VERSION-complete.jar" >&2
	exit 1
fi

classes=$(mktemp -d)
trap 'rm -rf "$classes"' EXIT

javac -nowarn -cp "$jar" -d "$classes" \
	"$here/src/org/antlr/v4/codegen/target/BooTarget.java"

# The templates live in the jar beside the class, where ANTLR looks for them.
cp -R "$here/resources/." "$classes/"

(cd "$classes" && jar --create --file "$here/antlr-boo-target.jar" .)

echo "build: wrote $here/antlr-boo-target.jar"
