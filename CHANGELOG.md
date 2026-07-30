# Changelog

This format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0]

First release.

### Added

- **Automatic Windows Terminal colouring based on the current directory.** The selected tab
  and the window border take the project colour at full strength, while the pane you read
  text in stays exactly as it was. Background tabs keep their own colour, and the tab row
  never follows the project.
- **Four colour sources**, nearest ancestor in the tree winning, the same way
  `.editorconfig` does: `.terminalcolors.json`, Peacock's `peacock.color` (VS Code),
  Solution Colors' `.vs/<Solution>/color.txt` (Visual Studio), and a colour derived from
  the Git repository name with an FNV-1a hash — stable, and identical on every machine.
- **Per-Git-branch colours**, with wildcards (`release/*`, `hotfix/*`), so you notice you
  are on a release branch before running a command.
- `Install-TerminalColorsTheme`: installs and selects the Windows Terminal theme that binds
  the tab and the border to the pane background. `settings.json` is edited by targeted
  insertion — comments, key order and formatting are preserved — with a backup, validation
  before writing, and `-WhatIf`. `-TabRowColor` chooses the colour the tab row is pinned to.
- `Install-TerminalColorsBackdrop`: lays an opaque image of your usual background colour
  over the pane, so `OSC 11` can carry the *pure* project colour without making the text
  unreadable. This is what decouples "tab colour" from "background colour", which the theme
  mechanism alone forces into a single channel. The images are solid PNGs encoded by the
  module itself, with no external dependency — `System.Drawing` is deliberately avoided
  since it is not guaranteed on PowerShell 7.
- `Install-TerminalColorsTitleBar`: writes `showTabsInTitlebar: false` so the window regains
  a real system title bar, which DWM colours through `DWMWA_CAPTION_COLOR`. Opt-in — it
  moves the tab strip below the title bar.
- `Install-TerminalColorsProfile`: a delimited block in the PowerShell profile, cleanly
  replaceable and removable, so the colouring is active in every new session.
- `Enable-TerminalColors`, with `-PureColor` (send the project colour undiluted, which the
  backdrop makes safe), `-Tint`, `-TitleFormat`, `-NoTitle`, `-NoIcons`, `-NoWindowBorder`,
  `-CaptionColor`, `-NoAutoGitColors`, `-BaseBackground`, `-ExplicitReset` and
  `-AlwaysReapply`.
- `Get-TerminalColor`, `Set-FolderColor`, `Remove-FolderColor`, `Update-TerminalColor`,
  `Reset-TerminalColor`, `Clear-TerminalColorCache`, and a `Test-`/`Uninstall-` counterpart
  for each installer.
- `Invoke-TerminalColorsDoctor`: names what would prevent the colouring from working —
  missing or outdated theme, a `tabColor` pinned on the profile,
  `suppressApplicationTitle`, `-PureColor` without the backdrop, a background image of your
  own overriding the backdrop, a Windows build too old — and where each surface takes its
  colour from.
- `install.ps1`: the whole setup in one command, no administrator rights, nothing installed
  outside your user profile. Switches: `-SkipTheme`, `-SkipBackdrop`, `-SystemTitleBar`,
  `-SkipProfile`, `-EnableArguments`, `-Force`, `-WhatIf`.
- bash / zsh variant for Git Bash and WSL, with verified parity on automatic colours.
- 190 tests with no external dependency, running on Windows PowerShell 5.1 and PowerShell 7.

### Notes on how it works

Three findings from measuring Windows Terminal rather than trusting the documentation, all
of which shaped the design:

- The **selected** tab is painted with its own background colour opaquely, while a
  **background** tab is composited at roughly 30 % opacity over the tab row. The tab row is
  therefore pinned to a fixed colour: that is what lets each background tab show its own
  colour instead of 70 % of its neighbour's, and it keeps the strip from following whichever
  project is in front.
- `DwmSetWindowAttribute(DWMWA_BORDER_COLOR)` **returns `S_OK` on a Windows Terminal window
  and changes nothing** — Windows Terminal draws its own frame. The border is coloured by
  the theme, through `window.frame`, which accepts `terminalBackground` and therefore
  follows the project exactly like the tab.
- Windows Terminal paints the tab from the background **colour**, never from the background
  **image**. That is precisely why the opaque backdrop works.

[Unreleased]: https://github.com/ceddup/TerminalColors/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ceddup/TerminalColors/releases/tag/v1.0.0
