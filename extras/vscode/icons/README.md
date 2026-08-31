Both files are rendered from `assets/boo.svg`, and need re-rendering when it
changes. They live here because vsce packages an extension from its own folder
and cannot reach outside it.

`boo-file.svg` squares the viewBox so a `.boo` file's icon is not flush against
the edges of its slot. `boo-128.png` is the extension's own icon, which VS Code
wants as a PNG.
