# Boo for VS Code

Syntax highlighting, a file icon, and editor behaviour for Boo: bracket
matching, comment toggling, indentation after a colon.

No language server, so nothing here needs a build of Boo. Diagnostics, hover
and go to definition are `boolsp`'s job and land separately.

Run it from the root of a clone:

```
code --extensionDevelopmentPath="$PWD/extras/vscode" .
```

That opens a second window with the extension loaded and this repository open,
which is a useful test: it holds several hundred `.boo` files.

The grammar's keywords come from `src/Boo.Lang.Parser/BooLexer.g4` and its
builtins from `src/Boo.Lang/Builtins.cs` and
`src/Boo.Lang.Compiler/TypeSystem/BuiltinFunction.cs`.

Boo accepts `#` and `//` for line comments and both are highlighted, but VS
Code takes only one marker for the toggle, which is `#`.
