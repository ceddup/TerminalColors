# Contributing

Thanks for taking a look. Issues, ideas and pull requests are all welcome.

## Language

**English everywhere**: documentation, source comments, comment-based help, error
messages, test names and CI step names. `README.fr.md` is the one exception — it is the
French translation of the README. If you change one README, change both, or say in your
pull request that the other still needs updating.

User-visible strings matter as much as the docs: an error message or a `Get-Help` synopsis
is read far more often than a comment.

## Getting set up

No build step, no dependency to install:

```powershell
git clone https://github.com/ceddup/TerminalColors.git
cd TerminalColors

Import-Module .\src\TerminalColors\TerminalColors.psd1 -Force
.\tests\Invoke-Tests.ps1
```

To try your changes for real without touching your installed copy, import the module from
the clone in a fresh tab and call `Enable-TerminalColors` by hand.

`Invoke-TerminalColorsDoctor` is the fastest way to see what state a machine is in.

## Running the tests

```powershell
.\tests\Invoke-Tests.ps1             # exit code 0 if everything passes
.\tests\Invoke-Tests.ps1 -Detailed   # list every passing test too
```

The suite is deliberately dependency-free — no Pester, nothing to install — so that
anyone can verify behaviour immediately, on Windows PowerShell 5.1 as well as
PowerShell 7. CI runs it on both.

Tests never touch your real settings: `settings.json` fixtures live in a temporary
sandbox, and the module's data directory (`%LOCALAPPDATA%\TerminalColors`) is redirected
there too.

**Please add a test with any behaviour change.** If a bug got through, that means the
suite was missing a case; the fix and the case belong in the same commit.

## House rules

A few constraints exist for concrete reasons, and a test enforces each of them:

- **Source is pure ASCII.** Windows PowerShell 5.1 reads a BOM-less file as ANSI, so a
  single accented character in a source file corrupts it on someone else's machine. Use
  `[char]27` rather than an escape literal, and write `[...]` instead of guillemets.
  Emoji in *output* are fine — they go through the Unicode console API.
- **No `Set-StrictMode` in the module.** It reads a lot of JSON whose properties are
  optional (`settings.json`, `.vscode/settings.json`), and strict mode would turn every
  absent property into an exception in the middle of the user's prompt hook. Optional
  reads go through `Get-TcJsonProperty`, which returns `$null` instead of throwing.
- **Windows PowerShell 5.1 compatibility.** No `??`, no ternary, no `` `e ``, and watch
  out for `0xFFFFFFFF` parsing as `Int32 -1`.
- **The prompt hook must never throw.** Anything that runs per-prompt is wrapped, and
  must stay cheap: no disk read when the directory has not changed.
- **`settings.json` is the user's file.** Every edit is surgical (comments, formatting and
  unrelated keys preserved), validated by re-parsing before writing, and backed up first.
- Public functions get comment-based help with at least `.SYNOPSIS` and one `.EXAMPLE`.
- Anything that writes to disk supports `-WhatIf`.

## Static analysis

CI runs PSScriptAnalyzer with the repository settings:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

`PSScriptAnalyzerSettings.psd1` documents why each excluded rule is excluded. If you need
a new exclusion, say why in the file rather than suppressing it silently.

## Pull requests

- Branch off `main`.
- Keep the commit history readable; small, self-contained commits are easier to review.
- Make sure `.\tests\Invoke-Tests.ps1` passes on the PowerShell edition you have.
- Update `CHANGELOG.md` under `## [Unreleased]`.
- Describe how you tested visually if the change affects the rendering — the tab, title
  bar and border are the one thing no test can assert.

## Reporting a bug

Please include the output of `Invoke-TerminalColorsDoctor` and your Windows Terminal
version. The issue template asks for both.
