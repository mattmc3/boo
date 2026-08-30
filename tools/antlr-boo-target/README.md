# The Boo code generation target for ANTLR 4

Makes `antlr4 -Dlanguage=Boo` write a lexer, parser and visitor in Boo instead
of C#. Boo runs on .NET, so the generated code uses `Antlr4.Runtime` exactly as
the C# target does and no separate runtime library is needed.

## Using it

```sh
java -cp antlr-4.13.1-complete.jar:tools/antlr-boo-target/antlr-boo-target.jar \
	org.antlr.v4.Tool -Dlanguage=Boo -package Foo -visitor -no-listener -o gen Foo.g4
```

ANTLR finds the target by reflection on `org.antlr.v4.codegen.target.BooTarget`
and its templates by classpath resource, so putting the jar on `-cp` is the
whole installation. There is no plugin registry to add to.

## The generated code is ordinary indented Boo

No `-wsa` needed. Blocks are laid out by indentation, and any block that can
come out empty is given a trailing `pass`.

That depends on `pass` being a no-op statement, which it became along with this
target. Before then it was an alternative to statements rather than one of them,
so it could not follow real code, and the templates had to emit whitespace
agnostic Boo and lean on `WSATokenStreamFilter` to inject a `pass` into empty
blocks.

Indentation is therefore load bearing. StringTemplate indents an interpolated
value by the indentation of the site it is written into, which is what carries
the nesting, with one trap: it drops the leading whitespace before an `<if>`
that has no `<else>`, so both branches have to carry the indent themselves.

## Building the jar

```sh
tools/antlr-boo-target/build.sh
```

Needs a JDK. The jar is committed so that nobody else does: generating a parser
needs only `java`, which is what `scripts/regenerate-parser.sh` already asks
for. Run the build after editing `BooTarget.java` or `Boo.stg`.

## Checking it

```sh
tools/antlr-boo-target/test/check.sh
tools/antlr-boo-target/test/check-boo-parser.sh
```

`check.sh` generates a parser for `test/Calc.g4`, compiles it with `booc`, and
runs `test/driver.boo` over it. The grammar covers left recursion, alternative
labels, token sets, loops and a generated visitor. Needs `booc` built under
`src/booc/bin`.

`check-boo-parser.sh` is the real one: it generates Boo's own lexer and parser
from `BooLexer.g4` and `BooParser.g4`, compiles them against the Boo companions
in `src/Boo.Lang.Parser`, and checks the result tokenises identically to the C#
parser the build actually uses. Also needs `Boo.Lang.Parser` built.

## How it is put together

`Boo.stg` takes its control flow from the Python 3 target, which faces the same
two gaps as Boo: no `switch` statement and no `do`-`while`. Alternatives become
an `if`/`elif` chain, and a `do`-`while` becomes `while true` with a trailing
`break unless`. Everything else follows the C# target, because that is the
runtime the generated code calls.

`BooTarget.java` is a copy of `CSharpTarget` carrying Boo's keywords instead of
C#'s. It does not override `escapeWord`: Boo has no verbatim identifier syntax,
a leading `@` being splice syntax in an AST literal, so the base class's
trailing underscore is the right escape. This matters for this repository in
particular, because `BooParser.g4` has a rule named `end`.

## What is proven, and what is not

`BooLexer.g4` and `BooParser.g4` now generate Boo that compiles and tokenises
identically to the C# parser, so lexer modes, custom channels, lexer actions and
semantic predicates are all exercised by `check-boo-parser.sh`.

Still unproven:

- listeners: the target is used with `-no-listener` here
- grammars with rule arguments or return values
- the parser beyond tokenising: the generated parse rules compile, but the C#
  support classes they need to build an AST have not been ported, so nothing has
  parsed a whole module through the Boo parser yet

Actions and predicates are written in the target language, so a grammar carrying
C# ones does not generate compilable Boo. That is inherent to ANTLR rather than
a limit of this target, and it is why both Boo grammars keep their actions to a
single call.

The generated code also draws `BCW0016` unused namespace warnings, since the
import list is fixed while the code that needs each namespace is not.
