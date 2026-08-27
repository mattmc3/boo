# ANTLR 2.7.5

Only the generator jar is kept here. It regenerates the Boo parser from
`src/Boo.Lang.Parser/boo.g` and `booel.g`, and still runs on current JDKs
(verified on OpenJDK 26):

    java -cp lib/antlr-2.7.5/antlr-2.7.5.jar antlr.Tool -o src/Boo.Lang.Parser src/Boo.Lang.Parser/boo.g

The generated parser is committed, so this is only needed when a grammar
changes. The ANTLR C# runtime Boo compiles against is vendored in
`src/Boo.Lang.Parser/antlr/`.
