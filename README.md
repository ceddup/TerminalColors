# TerminalColors

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/TerminalColors?logo=powershell&logoColor=white&label=PSGallery)](https://www.powershellgallery.com/packages/TerminalColors)
[![Downloads](https://img.shields.io/powershellgallery/dt/TerminalColors?label=downloads)](https://www.powershellgallery.com/packages/TerminalColors)
[![CI](https://github.com/ceddup/TerminalColors/actions/workflows/ci.yml/badge.svg)](https://github.com/ceddup/TerminalColors/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Windows Terminal changes colour when you `cd` into a project.**

*[Version française](README.fr.md)*

If you already use [Peacock](https://marketplace.visualstudio.com/items?itemName=johnpapa.vscode-peacock)
in VS Code or [Solution Colors](https://marketplace.visualstudio.com/items?itemName=MadsKristensen.SolutionColors)
in Visual Studio to tell your projects apart at a glance, TerminalColors brings the same
thing to Windows Terminal — **and reuses the colours you have already defined**.

```
PS C:\> cd C:\Repos\oseille          -> green tab, green window border
PS C:\Repos\oseille> cd ..\pastel    -> tab and border turn cyan
PS C:\Repos\pastel> cd C:\           -> back to normal
```

No third-party tool, no AutoHotkey, no background service: one PowerShell module, and
that is all.

---

## What gets coloured

| Element | How | When |
| --- | --- | --- |
| **Selected tab** | Windows Terminal theme bound to the pane background (`tab`) | on `cd`, at full strength |
| **Background tabs** | same mechanism, but Windows Terminal mutes them | on `cd`, each keeps its own colour |
| **Window border** | Windows Terminal theme (`window.frame`) | on `cd`, at full strength |
| **Tab title** | console API | on `cd` — `🟩 Oseille` |
| **System title bar** | `DwmSetWindowAttribute` | opt-in, see [System title bar](#system-title-bar) |

The project colour lands **pure** on the selected tab and on the border, while the pane you
actually read text in stays exactly as it was. That decoupling is what the opaque backdrop
is for — see [How it works](#how-it-works).

The tab row, on the other hand, **never changes colour**: it is pinned to your terminal's
own background so it does not take the colour of whichever project happens to be in front.

---

## Install

Requirements: Windows 11, Windows Terminal, PowerShell 5.1 or 7 (both are supported).
No administrator rights, nothing installed outside your user profile.

### From the PowerShell Gallery

```powershell
Install-Module TerminalColors -Scope CurrentUser
Import-Module TerminalColors

Install-TerminalColorsTheme        # makes the tab and the window border follow the colour
Install-TerminalColorsBackdrop     # keeps the pane readable while the tab stays vivid
Install-TerminalColorsProfile      # enables it in every new session
```

### From a clone

```powershell
git clone https://github.com/ceddup/TerminalColors.git
cd TerminalColors
.\install.ps1
```

`install.ps1` does all of the above in one go, plus activates the colouring in the
current session. Useful switches: `-SystemTitleBar`, `-SkipBackdrop`, `-Force`,
`-WhatIf`.

Then **open a new tab** and `cd` into one of your repositories.

### Check the install

```powershell
Invoke-TerminalColorsDoctor
```

This reports precisely what would prevent the colouring from working — missing theme,
a `tabColor` pinned on the profile, `suppressApplicationTitle`, an inconsistent
`-PureColor` without backdrop, a Windows build too old, and so on.

---

## Where the colour comes from

On every directory change TerminalColors walks up the tree. **The nearest folder that
defines a colour wins**, the same way `.editorconfig` works. Within a folder, the
priority is:

| Priority | Source | File read |
| --- | --- | --- |
| 1 | TerminalColors config | `.terminalcolors.json` |
| 2 | **Peacock** (VS Code) | `.vscode/settings.json` → `peacock.color` |
| 3 | **Solution Colors** (Visual Studio) | `.vs/<Solution>/color.txt` |
| 4 | Git repository | a `.git` is present → stable colour derived from the name |

So if your projects are already colour-coded in VS Code or Visual Studio, there is
**nothing to configure**: the same colours show up in the terminal. Every other Git
repository gets an automatic colour that is stable and identical on every machine
(derived from the repository name with an FNV-1a hash, not randomly).

To see the map of your repositories:

```powershell
Get-ChildItem C:\Repos -Directory | Get-TerminalColor | Format-Table Name, Color, Icon, Source

```

`Get-TerminalColor` also reports the exact file it picked (`SourcePath`), which is handy
when a colour surprises you.

---

## Setting a colour explicitly

```powershell
Set-FolderColor '#215732'                 # current folder
Set-FolderColor Teal -Path C:\Repos\sgi   # any known colour name
Set-FolderColor auto                      # stable colour derived from the project name
```

This writes a deliberately readable, source-controllable `.terminalcolors.json` —
**commit it and the whole team shares the project colour**:

```json
{
  "color": "#215732",
  "name": "Oseille"
}
```

Every available key:

```json
{
  "color": "#215732",
  "name": "FooProject",
  "icon": "🟩",
  "tint": 0.45,
  "applyToSubfolders": true,
  "branches": {
    "main": "#215732",
    "release/*": "#B71C1C",
    "hotfix/*": "OrangeRed"
  }
}
```

| Key | Purpose |
| --- | --- |
| `color` | hex code, known colour name, or `auto` |
| `name` | tab label (default: folder name) |
| `icon` | symbol before the label (default: a coloured square derived from the colour) |
| `tint` | background tint strength for this project, 0 to 1 (ignored with `-PureColor`) |
| `applyToSubfolders` | `false` to limit the colour to that one folder |
| `branches` | per-Git-branch colour, wildcards allowed, first match wins |

A JSON schema ships in [`schema/terminalcolors.schema.json`](schema/terminalcolors.schema.json)
for editor autocompletion.

Per-branch colours are a cheap way to notice you are on `release/*` or `hotfix/*`
*before* running a command.

---

## Settings

Behaviour is controlled by the `Enable-TerminalColors` line in your profile
(`$PROFILE.CurrentUserAllHosts`, editable by hand):

```powershell
Enable-TerminalColors -PureColor -TitleFormat '{icon} {name} ({folder})'
```

| Parameter | Effect |
| --- | --- |
| `-PureColor` | sends the project colour undiluted. Requires the opaque backdrop |
| `-Tint <0..1>` | background tint strength when not using `-PureColor` (default `0.30`) |
| `-TitleFormat` | title template. Tokens: `{icon}` `{name}` `{color}` `{folder}` `{path}` |
| `-NoTitle` | leave the tab title alone |
| `-NoIcons` | no coloured square before the label |
| `-NoWindowBorder` | skip the `DwmSetWindowAttribute` call (the border itself comes from the theme) |
| `-CaptionColor` | also colour the system title bar (needs `Install-TerminalColorsTitleBar`) |
| `-NoAutoGitColors` | only use explicitly declared colours |
| `-BaseBackground` | force the reference background colour used for blending |
| `-ExplicitReset` | on leaving a project, rewrite the background instead of emitting `OSC 111` |
| `-AlwaysReapply` | reapply on every prompt, not only on directory change — useful if a program resets the terminal background |

Other commands: `Disable-TerminalColors`, `Reset-TerminalColor`,
`Update-TerminalColor -Force`, `Clear-TerminalColorCache`, `Remove-FolderColor`, and the
`Install-`/`Uninstall-`/`Test-` trio for `TerminalColorsTheme`, `TerminalColorsBackdrop`,
`TerminalColorsTitleBar` and `TerminalColorsProfile`.

Every command has full help: `Get-Help Enable-TerminalColors -Full`.

---

## How it works

Windows Terminal exposes no API to recolour a tab on demand. TerminalColors combines
three native mechanisms instead.

**1. `OSC 11`** — the standard control sequence asking the terminal to change its
background colour. The module emits it on every directory change.

**2. The Windows Terminal theme** it installs declares
`"tab": { "background": "terminalBackground", "unfocusedBackground": "terminalBackground" }`
and `"window": { "frame": "terminalBackground", "unfocusedFrame": "terminalBackground" }`.
Windows Terminal then copies each pane's background colour onto its own tab and onto the
window border. This is what makes the colour visible where it matters, with no extra
process — and why the theme is mandatory.

The tab row is deliberately left out: it is pinned to a fixed colour so the strip never
takes the colour of whichever project is in front. See below — that pinning is also what
lets background tabs keep their own colour.

**3. The opaque backdrop** solves the problem those two create together. A theme accepts
only four values for `tab.background`: `terminalBackground`, `accent`, a fixed colour,
or nothing. The only one steerable at runtime is `terminalBackground` — meaning *tab
colour* and *background colour* are one and the same channel. Sending a vivid colour
would make the pane unreadable, which is why 1.0 diluted it to 30 %.

The backdrop decouples them: `OSC 11` sends the **pure** project colour, and an opaque
background image of your usual background colour is laid over the pane. Windows Terminal
paints the tab from the background *colour*, never from the *image* — so the tab becomes
vivid while the pane stays exactly as it was. The images are tiny PNGs generated by the
module in `%LOCALAPPDATA%\TerminalColors`.

**4. `DwmSetWindowAttribute`** — used only for the system title bar
(`DWMWA_CAPTION_COLOR`), which exists when the tabs are moved out of the title bar. It is
**not** what colours the window border: `DWMWA_BORDER_COLOR` returns `S_OK` on a Windows
Terminal window and changes nothing, because Windows Terminal draws its own frame. The
theme does that job (mechanism 2). The module locates the window by walking up the parent
process chain, and the interop is compiled on first use only, so it never slows session
startup.

Anything window-wide belongs to the *window*, not to the tab, so only the visible tab is
allowed to drive it: a tab compares the window title with the titles it has set, and keeps
its hands off when it is not the one on screen. It also refuses to *reset* a colour it never
applied — when several tabs start at once, a colourless tab restores the shell's default
title, which is exactly what the window shows until the active tab sets its own, so the title
alone is not enough to tell them apart.

### Why the tab row is pinned and the tabs are not

Measured, not assumed: the **selected** tab is painted with its own background colour
opaquely, while a **background** tab is composited at roughly 30 % opacity over the tab row.

So the row is the base every background tab is mixed into. When the row carried the active
project's colour, background tabs borrowed 70 % of it — a plain black tab next to a
`#215732` project measured `#1A4026`, and a `#61DAFB` one measured `#347E6E`: everything
turned green. Pinning the row to a fixed colour fixes that at the source, and it is also
what you want visually, since the strip then never follows whichever project is in front.

The consequence to know about: a background tab shows a **muted** version of its own colour,
not the full one. `#61DAFB` over a pinned `#0C0C0C` row comes out `#254953`. Windows Terminal
offers no per-tab value that is painted opaquely, so there is no way around it.

The prompt hook wraps your existing `prompt` function (oh-my-posh, Starship or your
own), which stays intact and is restored by `Disable-TerminalColors`. It does nothing at
all until the directory changes, and resolution is cached with invalidation on the source
file's modification time, so the per-prompt cost is negligible.

### System title bar

By default Windows Terminal draws its tabs *inside* the title bar, so the window has no
real system title bar. `Install-TerminalColorsTitleBar` writes
`showTabsInTitlebar: false`, which gives the window a genuine system title bar that DWM
colours directly — pure colour, immediately, without going through the background.

The trade-off: the tab strip moves below the title bar. Requires a full Windows Terminal
restart, and `Enable-TerminalColors -CaptionColor` to actually apply the colour.

### Does it keep working?

Set once and done: the module lives in your personal modules, the activation block in
your profile, the theme and backdrop in `settings.json`. The colouring therefore comes
back in every new tab and after every reboot, and Windows Terminal updates do not touch
those settings. No service, no scheduled task, no resident process — nothing that can
"stop running".

The only three things that can disable it, all reversible:

1. **Selecting another theme** in Windows Terminal settings (Appearance → Theme). Fix:
   `Install-TerminalColorsTheme`.
2. **Right-click a tab → Color…**, or a `tabColor` in a profile: that manual colour
   overrides the theme and pins the tab. Fix: remove it.
3. **Another custom prompt installed afterwards** (oh-my-posh, Starship) redefining
   `prompt` and overwriting the hook. Fix: put the `Enable-TerminalColors` call **after**
   its initialisation in your profile.

In all three cases `Invoke-TerminalColorsDoctor` names the problem and the fix.

### Known limitations

- **A background tab shows a muted version of its colour**, not the full one — Windows
  Terminal composites it at about 30 % opacity over the tab row, and offers no per-tab value
  that is painted opaquely. `#61DAFB` over a pinned `#0C0C0C` row comes out `#254953`. The
  selected tab and the window border carry the exact project colour.
- **The window border is one pixel wide.** Windows sets that thickness, and neither the theme
  nor `DwmSetWindowAttribute` exposes a width. If you want a large coloured surface,
  `Install-TerminalColorsTitleBar` gives you a full system title bar instead.
- **The border needs a Windows Terminal recent enough to support `window.frame`** in themes
  (1.19+). On older versions the tab still works, and the module falls back to
  `DwmSetWindowAttribute` — which does nothing on Windows Terminal, but is harmless.
- A `tabColor` set on a Windows Terminal profile **overrides the theme** and pins the tab
  colour. `Invoke-TerminalColorsDoctor` reports it.
- The opaque backdrop replaces `profiles.defaults.backgroundImage`. If you already use a
  background image, keep `-SkipBackdrop` and the diluted 1.0 rendering.
- A `backgroundImage` set on an **individual profile** overrides `profiles.defaults`, so
  the backdrop has no effect in that profile. `Invoke-TerminalColorsDoctor` names the
  profiles concerned.
- The backdrop pins the pane to the colour it had when installed. If you later change your
  colour scheme, run `Install-TerminalColorsBackdrop` again to regenerate it.
- Border colouring requires Windows 11 (build 22000+). On Windows 10 the tab and title
  bar work normally.
- Outside Windows Terminal (conhost, the VS Code integrated terminal) the module stays
  silent by default, so it never prints stray characters.

---

## Git Bash, WSL, zsh

A lighter variant ships in [`shell/terminalcolors.sh`](shell/terminalcolors.sh): same
colour resolution, same automatic colours (parity with the PowerShell module is asserted
in CI), without the window border, which needs a Windows API.

```bash
mkdir -p ~/.local/share/terminalcolors
cp shell/terminalcolors.sh ~/.local/share/terminalcolors/
echo 'source ~/.local/share/terminalcolors/terminalcolors.sh' >> ~/.bashrc
```

Configured through environment variables: `TERMINALCOLORS_TINT`, `TERMINALCOLORS_BASE`,
`TERMINALCOLORS_TITLE`, `TERMINALCOLORS_ICONS`, `TERMINALCOLORS_AUTOGIT`.

---

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Nothing happens | `Invoke-TerminalColorsDoctor` — nine times out of ten the theme is not installed or not selected |
| The colouring only appears in new tabs | expected: the hook is installed by the profile, which existing sessions never re-read |
| The background changes but not the tab | theme missing, or `tabColor` set on the profile |
| The tab changes but not its title | `suppressApplicationTitle` or `tabTitle` set on the profile |
| The whole pane turns vivid and text is unreadable | `-PureColor` without the backdrop: run `Install-TerminalColorsBackdrop` |
| The tab colour is washed out | the backdrop is missing; without it the colour has to be diluted |
| The background is too colourful | lower `-Tint` (try `0.18`) |
| A colour is wrong | `Get-TerminalColor` shows the exact file it used |
| A config file was just edited | `Clear-TerminalColorCache; Update-TerminalColor -Force` |
| The colour vanished after running a program | that program reset the background: `Update-TerminalColor -Force`, or enable `-AlwaysReapply` |
| You changed theme in Windows Terminal settings | the `TerminalColors` theme was deselected: `Install-TerminalColorsTheme` |

Every change to `settings.json` writes a
`settings.json.terminalcolors-backup-<timestamp>` copy next to the file.

---

## Uninstall

```powershell
Uninstall-TerminalColorsProfile     # remove the block from the profile
Uninstall-TerminalColorsBackdrop    # remove the opaque layer and its images
Uninstall-TerminalColorsTitleBar    # restore tabs in the title bar, if enabled
Uninstall-TerminalColorsTheme       # remove the theme and restore the previous one
Disable-TerminalColors              # restore the current session's appearance
Uninstall-Module TerminalColors     # or delete the folder for a clone install
```

---

## Development

```powershell
.\tests\Invoke-Tests.ps1            # 190 tests, no dependency
.\tests\Invoke-Tests.ps1 -Detailed
```

The tests cover colour parsing, comment-tolerant JSON, Git detection (worktrees
included), all four colour sources and their priorities, the cache, the control
sequences, and `settings.json` editing (comments preserved, idempotence, refusal to write
invalid JSON, `-WhatIf`) — for the theme, the opaque backdrop and the system title bar
alike, including the legacy array-shaped `profiles` and refusing to silently discard a
background image you set yourself.

The backdrop PNG encoder is checked byte by byte: signature, `IHDR` fields, every chunk
CRC, the zlib header and its Adler-32 — plus a decode through `System.Drawing` when that
assembly is available.

Source code is **pure ASCII** — a test enforces it — so no encoding problem can arise
between Windows PowerShell 5.1, PowerShell 7 and everyone's editor.

See [CONTRIBUTING.md](CONTRIBUTING.md) to get started, and
[docs/PUBLISHING.md](docs/PUBLISHING.md) for the release process.

---

## License

MIT — see [LICENSE](LICENSE).

