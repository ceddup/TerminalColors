# Security Policy

## Supported versions

The latest published version on the PowerShell Gallery is the supported one. Fixes are
released as a new version rather than backported.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/ceddup/TerminalColors/security/advisories/new).

Expect an acknowledgement within a few days. If a fix is warranted, it ships as a new
version and the advisory is published alongside it, crediting you unless you would rather
stay anonymous.

## What this module touches

Useful context when assessing a report. TerminalColors runs entirely with the rights of
the user who installed it — it never requires administrator rights and installs nothing
outside the user profile. It does write to three places:

| Path | Why |
| --- | --- |
| Windows Terminal `settings.json` | adds the theme, the opaque backdrop, and optionally `showTabsInTitlebar` |
| `$PROFILE.CurrentUserAllHosts` | a delimited block that imports the module and calls `Enable-TerminalColors` |
| `%LOCALAPPDATA%\TerminalColors` | install state and the generated backdrop PNG files |

Each `settings.json` edit is validated by re-parsing before writing and preceded by a
`settings.json.terminalcolors-backup-<timestamp>` copy.

It also **reads** files inside the directories you `cd` into: `.terminalcolors.json`,
`.vscode/settings.json`, `.vs/*/color.txt`, and `.git/HEAD`. Values read from those files
are treated as data — a colour is parsed and rejected if it is not a valid hex code or a
known colour name, and nothing read from a repository is ever executed. That matters
because `cd`-ing into a repository cloned from an untrusted source causes those files to
be read.

Window border and title bar colouring calls `DwmSetWindowAttribute` through a small
`Add-Type` interop compiled at first use. It only ever sets colour attributes, on a window
belonging to the Windows Terminal process hosting the current session.
