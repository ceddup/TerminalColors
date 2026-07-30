# Publishing

Maintainer runbook. Two things get published: the GitHub repository, and the module on the
PowerShell Gallery.

---

## One-time setup

### 1. Replace the `OWNER` placeholder

Repository URLs are written with `OWNER` as a placeholder. Replace them everywhere:

```powershell
.\tools\Set-RepositoryOwner.ps1 -Owner your-github-account -WhatIf   # check first
.\tools\Set-RepositoryOwner.ps1 -Owner your-github-account
```

This touches the manifest (`ProjectUri`, `LicenseUri`, `ReleaseNotes`), both READMEs and
their badges, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md` links, and the issue
template links.

### 2. Create the GitHub repository and push

```powershell
git branch -M main
git add -A
git commit -m "Initial public release"

git remote add origin https://github.com/your-github-account/TerminalColors.git
git push -u origin main
```

Then, in the repository settings:

- **Description**: *Windows Terminal changes colour when you `cd` into a project. Reuses
  your Peacock and Solution Colors colours.*
- **Topics**: `windows-terminal`, `powershell`, `powershell-module`, `peacock`,
  `developer-tools`, `windows-11`, `terminal`, `productivity`
- **Features**: enable Discussions (the issue template links to it), disable Wiki and
  Projects unless you want them.
- **Code of conduct**: Insights → Community Standards → *Add* next to Code of conduct.
  Use GitHub's own template so the Contributor Covenant text is exact.
- **Security**: Settings → Code security → enable *Private vulnerability reporting*, which
  is what `SECURITY.md` points at.
- **Branch protection** on `main` (optional but recommended): require the CI check to pass.

### 3. PowerShell Gallery API key

1. Sign in on [powershellgallery.com](https://www.powershellgallery.com/) with a Microsoft
   account.
2. Account → **API Keys** → *Create*. Scope it: `Push new packages and package versions`,
   glob pattern `TerminalColors`, expiry 365 days. A key scoped to one package cannot be
   used to hijack anything else if it leaks.
3. Copy the key — it is shown once.
4. In GitHub: Settings → Secrets and variables → Actions → **New repository secret**, named
   `PSGALLERY_API_KEY`. Or, from a terminal, `gh secret set PSGALLERY_API_KEY`, which reads
   the value without echoing it.

> **The key expires, and its expiry is invisible from here.** The one in use was created on
> 30 July 2026 with a 365-day life, so it stops working on **30 July 2027**. When that
> happens, `publish.yml` fails on its *Dry run* step with a 403 that says nothing about the
> real cause, on a commit that changed nothing relevant — an hour lost looking in the wrong
> place. Renew the key the same way, with the same scope and glob, then overwrite the
> secret. Nothing else needs touching: the workflow reads the secret by name.

The publish workflow declares `environment: powershell-gallery`. Either create that
environment (Settings → Environments) — where you can add a required reviewer so no
release publishes without your click — or remove the `environment:` line from
`.github/workflows/publish.yml`.

> The module name `TerminalColors` was free at the time of writing. Whoever pushes the
> first version owns it. Check with
> `Find-Module TerminalColors` before assuming it still is.

---

## Releasing a version

1. **Bump `ModuleVersion`** in `src/TerminalColors/TerminalColors.psd1`
   ([SemVer](https://semver.org/): breaking → major, feature → minor, fix → patch).
2. **Update `CHANGELOG.md`**: move `## [Unreleased]` entries under the new version, and add
   the compare links at the bottom.
3. **Update `ReleaseNotes`** in the manifest — that text is what the Gallery displays.
4. **Check the test count** quoted in both READMEs if you added tests.
5. **Run everything locally**:

   ```powershell
   .\tests\Invoke-Tests.ps1
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
   Test-ModuleManifest .\src\TerminalColors\TerminalColors.psd1
   ```

6. **Commit, tag, push**. The tag must be `v` + the manifest version — the workflow fails
   the release otherwise:

   ```powershell
   git commit -am "Release 1.0.0"
   git tag v1.0.0
   git push origin main --tags
   ```

7. **Create the GitHub release** from that tag, pasting the changelog section as the body.
   Publishing the release triggers `publish.yml`, which re-runs the tests on both
   PowerShell editions, refuses a version already on the Gallery, and pushes the package.

8. **Verify**, a few minutes later (Gallery indexing is not instant):

   ```powershell
   Find-Module TerminalColors
   Install-Module TerminalColors -Scope CurrentUser -Force
   ```

### Publishing by hand

Only needed if Actions is unavailable. Windows PowerShell 5.1 ships PowerShellGet 1.0.0.1,
which is too old to publish reliably — update it first:

```powershell
Install-Module PowerShellGet -Force -AllowClobber -Scope CurrentUser
# then, in a NEW session:
Publish-Module -Path .\src\TerminalColors -NuGetApiKey <key> -WhatIf   # dry run first
Publish-Module -Path .\src\TerminalColors -NuGetApiKey <key>
```

`-Path` points at the folder holding the `.psd1`. Everything in that folder is packaged,
so keep it free of stray files.

**A published version can never be replaced.** The Gallery only allows unlisting, which
hides it without freeing the version number. A dry run costs nothing; do it.

---

## Getting the word out

Somewhere to start, roughly in order of return:

- A **short screen recording** in the README is worth more than every paragraph in it. The
  whole pitch is visual, and right now a visitor has to imagine it. Record `cd` between
  three coloured repositories, keep it under ten seconds, drop it in `docs/`.
- [r/PowerShell](https://reddit.com/r/PowerShell) and
  [r/Windows11](https://reddit.com/r/Windows11) — lead with the problem, not the module.
- The **Peacock** and **Solution Colors** repositories: an issue or discussion saying
  "here is the terminal equivalent, it reads your existing config" reaches exactly the
  people who already want this.
- [Awesome PowerShell](https://github.com/janikvonrotz/awesome-powershell) — a pull
  request adding one line.
- The [Windows Terminal](https://github.com/microsoft/terminal) discussions: dynamic tab
  colours are a recurring request, and this is a working answer that needs no new API.
- Internally: `install.ps1` from the clone is the one command your colleagues need.
