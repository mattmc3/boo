# gitutils

Small git helpers in Boo. Shows generators, list comprehensions, string
interpolation, regular expression literals and `shell`.

`git.boo` holds the shared functions. Each script is compiled together with it,
because a module sees another module's top level methods only when both are in
the same compilation:

```
booc -target:exe -out:git_untracked.exe src/git_untracked.boo src/git.boo
```

| Script | Does |
|---|---|
| `git_changed.boo` | prints every tracked file with changes |
| `git_untracked.boo` | prints every file git is not tracking |
| `git_ignore_all.boo` | asks about each untracked file, appends to `.gitignore` |

Status comes from `git status --porcelain`, whose format is two status columns,
a space, then the path. The path is taken by position rather than by splitting
on whitespace, so names containing spaces survive. Such names are printed the
way git quotes them.
