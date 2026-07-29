# Changelog

This format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0]

Pure colour on the tab, the title bar and the border — without touching the pane you
read text in.

### Added

- **Opaque backdrop** (`Install-TerminalColorsBackdrop`): an opaque background image of
  your usual background colour is laid over the pane, so `OSC 11` can carry the *pure*
  project colour for Windows Terminal to copy onto the tab and title bar. This decouples
  "tab colour" from "background colour", which the theme mechanism alone forces into a
  single channel.
- `Enable-TerminalColors -PureColor`: send the project colour undiluted. Reported as
  inconsistent by the doctor when the backdrop is missing.
- **System title bar** (`Install-TerminalColorsTitleBar`): writes
  `showTabsInTitlebar: false` so the window regains a real system title bar, which DWM
  colours directly through `DWMWA_CAPTION_COLOR`.
- `Test-TerminalColorsBackdrop`, `Test-TerminalColorsTitleBar`, and the matching
  `Uninstall-` commands.
- `install.ps1`: installs the backdrop by default and adds `-PureColor` to the profile
  block accordingly. New switches `-SkipBackdrop` and `-SystemTitleBar`.
- Solid-PNG generation with no external dependency, for the backdrop images
  (`%LOCALAPPDATA%\TerminalColors`). `System.Drawing` is deliberately avoided: it is not
  guaranteed on PowerShell 7.
- 35 tests, bringing the suite to 161.

### Changed

- Default rendering is now pure colour on the tab rather than a 30 % dilution.
  `-SkipBackdrop` keeps the 1.0 behaviour.
- `settings.json` editing helpers moved to `Private\WtSettings.ps1`, now shared by the
  three installers.
- The colour actually sent to the terminal is decided by `Get-TcEffectiveBackground`,
  which no longer reads `settings.json` at all in pure-colour mode.
- The module's data directory can be redirected, so the test suite never touches the real
  `%LOCALAPPDATA%\TerminalColors`.

## [1.0.0]

Initial release.

### Added

- Automatic Windows Terminal colouring based on the current directory: tab and title bar
  through a Windows Terminal theme bound to the pane background (`OSC 11`), window border
  through `DwmSetWindowAttribute`, tab title with a coloured square.
- Four colour sources, nearest ancestor in the tree winning: `.terminalcolors.json`,
  Peacock's `peacock.color` (VS Code), Solution Colors' `.vs/<Solution>/color.txt`
  (Visual Studio), and a stable colour derived from a Git repository name.
- Per-Git-branch colours, with wildcards (`release/*`).
- `Install-TerminalColorsTheme`: targeted `settings.json` editing that preserves comments
  and formatting, with a backup, validation before writing, and `-WhatIf`.
- `Install-TerminalColorsProfile`: a delimited block in the PowerShell profile, cleanly
  replaceable and removable.
- `Invoke-TerminalColorsDoctor`: diagnoses the installation and the Windows Terminal
  settings that would neutralise the colouring.
- `install.ps1`: complete installation in one command, no administrator rights.
- bash / zsh variant (Git Bash, WSL) with automatic-colour parity.
- `-AlwaysReapply`: reapply the colour on every prompt, for cases where a program resets
  the terminal background.
- 126 tests with no external dependency, running on PowerShell 5.1 and 7.

[Unreleased]: https://github.com/ceddup/TerminalColors/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ceddup/TerminalColors/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ceddup/TerminalColors/releases/tag/v1.0.0
