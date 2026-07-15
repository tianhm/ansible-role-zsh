# Windows (PowerShell + cmd) Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone `install.ps1` that gives native Windows PowerShell (and cmd.exe via clink) a starship-prompt + fzf/autosuggestion/history shell experience mirroring this role's zsh setup, without Ansible, Python, or WSL.

**Architecture:** A self-contained PowerShell script at the repo root detects a preinstalled package manager (winget → scoop → choco), installs `starship`/`fzf`/`clink` binaries and the `PSFzf`/`posh-git` PS modules, delivers a pre-rendered `windows/starship.toml`, and writes an idempotent managed block into the PowerShell profile. All pure logic (package-manager detection, feature resolution, profile-block merge) lives in dot-sourceable functions unit-tested with Pester; side-effectful install is verified end-to-end by a `windows-latest` GitHub Actions job. A Python render harness keeps `windows/starship.toml` from drifting from the Ansible Jinja template.

**Tech Stack:** PowerShell 5.1+/7+, Pester (PS tests), winget/scoop/choco, starship, fzf, clink, PSFzf, posh-git, PSReadLine; Python 3 + Jinja2/PyYAML (render harness) run in a `.venv`.

## Global Constraints

- Managed-block markers, verbatim: start `# >>> viasite-ansible zsh >>>`, end `# <<< viasite-ansible zsh <<<`.
- Package-manager probe order: `winget` → `scoop` → `choco`; require one; if none, print install links for all three and exit 1.
- All PS modules installed with `-Scope CurrentUser`.
- starship config path (both shells): `%USERPROFILE%\.config\starship.toml` (i.e. `$HOME\.config\starship.toml`).
- PSReadLine feature floors: prediction (`-PredictionSource History`) requires PSReadLine ≥ 2.1.0; `-PredictionViewStyle ListView` requires ≥ 2.2.0. Below the floor, silently omit those lines (never emit a profile that errors on shell start).
- cmd.exe receives **only** the starship prompt (via clink). PSReadLine and PSFzf are PowerShell-only.
- The ~25 zsh antigen completion bundles are **not ported**; the curated Windows feature set is starship, PSReadLine prediction, PSFzf, posh-git — each individually disableable by a `-No*` flag.
- Test-run gating env var: when `ZSH_INSTALL_NO_RUN` is set, `install.ps1` defines its functions but does **not** run the installer (so Pester can dot-source it).
- Python work uses a project `.venv` (per user global rule).
- Every profile-block line is emitted only when its feature is both flag-enabled and actually available.

---

### Task 1: Static `starship.toml` render harness + committed config + drift guard

Produces the single source of truth for the Windows prompt config: a Python harness that renders `templates/starship.toml.j2` with role defaults, the committed rendered output, and a pytest that fails if they diverge.

**Files:**
- Create: `windows/render_starship_config.py`
- Create: `windows/requirements-dev.txt`
- Create: `windows/starship.toml` (generated output, committed)
- Test: `windows/test_render_starship_config.py`

**Interfaces:**
- Produces: `windows/render_starship_config.py` prints the rendered starship TOML to stdout; `windows/starship.toml` is its committed output. Consumed by Task 4 (delivered to users) and Task 5 (CI drift check).

- [ ] **Step 1: Create the dev requirements file**

Create `windows/requirements-dev.txt`:

```
jinja2>=3.0
PyYAML>=6.0
pytest>=7.0
```

- [ ] **Step 2: Set up the venv and install deps**

Run:
```bash
python3 -m venv .venv
.venv/bin/pip install -r windows/requirements-dev.txt
```
Expected: installs jinja2, PyYAML, pytest without error.

- [ ] **Step 3: Write the render harness**

Create `windows/render_starship_config.py`:

```python
#!/usr/bin/env python3
"""Render templates/starship.toml.j2 with role defaults to stdout.

Single source of truth for windows/starship.toml. CI diffs this output against
the committed file so the Windows prompt never drifts from the Ansible default.
Only the variables the template actually references are needed; none of them
depend on Ansible facts, so the render is deterministic.
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ROLE_ROOT = Path(__file__).resolve().parent.parent
ANSIBLE_MANAGED = (
    "Managed by ansible-role-zsh (windows/render_starship_config.py) - do not edit"
)


def render() -> str:
    defaults = yaml.safe_load((ROLE_ROOT / "defaults" / "main.yml").read_text())
    ctx = dict(defaults)
    ctx["ansible_managed"] = ANSIBLE_MANAGED
    # _bool helpers normally computed in vars/main.yml:
    ctx["zsh_powerlevel9k_prompt_on_newline_bool"] = (
        "true" if defaults["zsh_powerlevel9k_prompt_on_newline"] else "false"
    )
    ctx["zsh_powerlevel9k_always_show_user_bool"] = (
        "true" if defaults["zsh_powerlevel9k_always_show_user"] else "false"
    )
    template_text = (ROLE_ROOT / "templates" / "starship.toml.j2").read_text()
    env = Environment(undefined=StrictUndefined, keep_trailing_newline=True)
    return env.from_string(template_text).render(**ctx)


if __name__ == "__main__":
    sys.stdout.write(render())
```

- [ ] **Step 4: Write the failing test**

Create `windows/test_render_starship_config.py`:

```python
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMMITTED = ROOT / "starship.toml"


def _render() -> str:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "render_starship_config.py")],
        capture_output=True, text=True, check=True,
    )
    return proc.stdout


def test_render_contains_expected_prompt_segments():
    out = _render()
    assert 'format = "$username$hostname$directory"' in out
    assert "[git_branch]" in out
    assert "[cmd_duration]" in out


def test_committed_config_is_not_stale():
    assert COMMITTED.exists(), "run: python windows/render_starship_config.py > windows/starship.toml"
    assert COMMITTED.read_text() == _render(), (
        "windows/starship.toml is stale; regenerate with "
        "`python windows/render_starship_config.py > windows/starship.toml`"
    )
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `.venv/bin/python -m pytest windows/test_render_starship_config.py -v`
Expected: `test_render_contains_expected_prompt_segments` PASSES; `test_committed_config_is_not_stale` FAILS with the "run: ..." assertion (file not created yet).

- [ ] **Step 6: Generate the committed config**

Run: `.venv/bin/python windows/render_starship_config.py > windows/starship.toml`
Then inspect it:
Run: `head -5 windows/starship.toml`
Expected: first line `# Managed by ansible-role-zsh (windows/render_starship_config.py) - do not edit`, and a `format = "$username$hostname$directory"` line further down.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `.venv/bin/python -m pytest windows/test_render_starship_config.py -v`
Expected: both tests PASS.

- [ ] **Step 8: Commit**

```bash
git add windows/render_starship_config.py windows/requirements-dev.txt windows/starship.toml windows/test_render_starship_config.py
git commit -m "feat(windows): render static starship.toml with drift guard"
```

---

### Task 2: `install.ps1` scaffold + package-manager detection

Creates the self-contained script shell: param block, marker constants, a guarded entrypoint (so Pester can dot-source it), and `Get-ZshPackageManager`. Establishes the Pester test file.

**Files:**
- Create: `install.ps1`
- Test: `windows/Windows.Tests.ps1`

**Interfaces:**
- Produces: `install.ps1` param set `-NoCmd -NoAutosuggestions -NoPSFzf -NoPoshGit -Force -PackageManager`; constants `$script:ZshBlockStart`, `$script:ZshBlockEnd`; function `Get-ZshPackageManager [-Prefer <string>]` → package-manager name string or `$null`. Consumed by Tasks 3 and 4.

**Local testing prerequisite:** these steps need `pwsh` + Pester. If absent locally, install PowerShell (Ubuntu: Microsoft `packages-microsoft-prod.deb`, then `apt-get install -y powershell`) and `pwsh -c "Install-Module Pester -Scope CurrentUser -Force"`. Otherwise these tests are verified by the CI job in Task 5.

- [ ] **Step 1: Create the script scaffold with detection**

Create `install.ps1`:

```powershell
[CmdletBinding()]
param(
    [switch]$NoCmd,
    [switch]$NoAutosuggestions,
    [switch]$NoPSFzf,
    [switch]$NoPoshGit,
    [switch]$Force,
    [ValidateSet('winget', 'scoop', 'choco')]
    [string]$PackageManager
)

Set-StrictMode -Version Latest

$script:ZshBlockStart = '# >>> viasite-ansible zsh >>>'
$script:ZshBlockEnd   = '# <<< viasite-ansible zsh <<<'
$script:WingetIds     = @{ starship = 'Starship.Starship'; fzf = 'junegunn.fzf'; clink = 'chrisant996.Clink' }

function Get-ZshPackageManager {
    param([string]$Prefer)
    $order = if ($Prefer) { @($Prefer) } else { @('winget', 'scoop', 'choco') }
    foreach ($pm in $order) {
        if (Get-Command $pm -ErrorAction SilentlyContinue) { return $pm }
    }
    return $null
}

# ---- entrypoint (skipped when dot-sourced for tests) ----
if (-not $env:ZSH_INSTALL_NO_RUN) {
    Invoke-ZshWindowsInstall @PSBoundParameters
}
```

Note: `Invoke-ZshWindowsInstall` is added in Task 4. Until then the script is only exercised dot-sourced (with `ZSH_INSTALL_NO_RUN` set), so the missing function does not matter for tests.

- [ ] **Step 2: Write the failing Pester test**

Create `windows/Windows.Tests.ps1`:

```powershell
$env:ZSH_INSTALL_NO_RUN = '1'
. "$PSScriptRoot/../install.ps1"

Describe 'Get-ZshPackageManager' {
    It 'returns the first available manager in winget->scoop->choco order' {
        Mock Get-Command { $true } -ParameterFilter { $Name -eq 'scoop' }
        Mock Get-Command { $null } -ParameterFilter { $Name -in @('winget', 'choco') }
        Get-ZshPackageManager | Should -Be 'scoop'
    }

    It 'returns $null when no manager is present' {
        Mock Get-Command { $null }
        Get-ZshPackageManager | Should -BeNullOrEmpty
    }

    It 'honors -Prefer when that manager exists' {
        Mock Get-Command { $true }
        Get-ZshPackageManager -Prefer 'choco' | Should -Be 'choco'
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -c "Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed"`
Expected: FAILS — either the file/function isn't found yet on the first authoring pass, or (if Steps done out of order) the mocks aren't wired. Confirm the `Get-ZshPackageManager` describe block is the one failing.

- [ ] **Step 4: Run the test to verify it passes**

(The implementation from Step 1 already satisfies it.)
Run: `pwsh -c "Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed"`
Expected: all three `Get-ZshPackageManager` tests PASS.

- [ ] **Step 5: Verify dot-sourcing does not run the installer**

Run: `pwsh -c "\$env:ZSH_INSTALL_NO_RUN='1'; . ./install.ps1; 'loaded ok'"`
Expected: prints `loaded ok` with no attempt to install anything (no error about missing `Invoke-ZshWindowsInstall`).

- [ ] **Step 6: Commit**

```bash
git add install.ps1 windows/Windows.Tests.ps1
git commit -m "feat(windows): install.ps1 scaffold with package-manager detection"
```

---

### Task 3: Feature resolution + profile-body builder + idempotent block merge

Adds the pure logic that turns flags + availability into a feature set, renders the managed-block body, and merges it into existing profile content idempotently. This is the heart of "disable unsupported plugins."

**Files:**
- Modify: `install.ps1` (add three functions before the entrypoint)
- Test: `windows/Windows.Tests.ps1` (add describe blocks)

**Interfaces:**
- Consumes: `$script:ZshBlockStart`, `$script:ZshBlockEnd` from Task 2.
- Produces:
  - `Resolve-ZshFeatures [-Params <hashtable>] [-Available <hashtable>]` → hashtable with keys `Autosuggestions`, `PredictionListView`, `PSFzf`, `PoshGit` (all bool).
  - `Get-ZshProfileBody [-Features <hashtable>]` → string (block body, no markers).
  - `Set-ZshManagedBlock [-Content <string>] -Body <string>` → string (full profile content with the managed region replaced or appended).
  - Consumed by Task 4's orchestrator.

- [ ] **Step 1: Write the failing tests**

Append to `windows/Windows.Tests.ps1`:

```powershell
Describe 'Resolve-ZshFeatures' {
    $allAvail = @{ PSReadLinePrediction = $true; PSReadLineListView = $true; PSFzf = $true; PoshGit = $true }

    It 'enables everything when no flags set and all available' {
        $f = Resolve-ZshFeatures -Params @{} -Available $allAvail
        $f.Autosuggestions   | Should -BeTrue
        $f.PredictionListView| Should -BeTrue
        $f.PSFzf             | Should -BeTrue
        $f.PoshGit           | Should -BeTrue
    }

    It 'disables PSFzf when -NoPSFzf even if available' {
        $f = Resolve-ZshFeatures -Params @{ NoPSFzf = $true } -Available $allAvail
        $f.PSFzf | Should -BeFalse
    }

    It 'disables autosuggestions when PSReadLine prediction unavailable' {
        $avail = @{ PSReadLinePrediction = $false; PSReadLineListView = $false; PSFzf = $true; PoshGit = $true }
        $f = Resolve-ZshFeatures -Params @{} -Available $avail
        $f.Autosuggestions    | Should -BeFalse
        $f.PredictionListView | Should -BeFalse
    }

    It 'requires PSReadLine >= 2.2 for ListView' {
        $avail = @{ PSReadLinePrediction = $true; PSReadLineListView = $false; PSFzf = $true; PoshGit = $true }
        $f = Resolve-ZshFeatures -Params @{} -Available $avail
        $f.Autosuggestions    | Should -BeTrue
        $f.PredictionListView | Should -BeFalse
    }
}

Describe 'Get-ZshProfileBody' {
    It 'always includes the starship prompt init' {
        Get-ZshProfileBody -Features @{} | Should -Match 'starship init powershell'
    }
    It 'includes PSFzf bindings only when enabled' {
        (Get-ZshProfileBody -Features @{ PSFzf = $true })  | Should -Match 'PSFzf'
        (Get-ZshProfileBody -Features @{ PSFzf = $false }) | Should -Not -Match 'PSFzf'
    }
    It 'includes ListView line only when PredictionListView enabled' {
        (Get-ZshProfileBody -Features @{ Autosuggestions = $true; PredictionListView = $true })  | Should -Match 'ListView'
        (Get-ZshProfileBody -Features @{ Autosuggestions = $true; PredictionListView = $false }) | Should -Not -Match 'ListView'
    }
}

Describe 'Set-ZshManagedBlock' {
    It 'appends a fresh block to empty content' {
        $r = Set-ZshManagedBlock -Content '' -Body 'BODYLINE'
        $r | Should -Match ([regex]::Escape($script:ZshBlockStart))
        $r | Should -Match 'BODYLINE'
    }
    It 'preserves existing user content' {
        $r = Set-ZshManagedBlock -Content "Write-Host hello" -Body 'BODYLINE'
        $r | Should -Match 'Write-Host hello'
        $r | Should -Match 'BODYLINE'
    }
    It 'replaces an existing block in place and stays single (idempotent)' {
        $first  = Set-ZshManagedBlock -Content 'user-line' -Body 'OLD'
        $second = Set-ZshManagedBlock -Content $first -Body 'NEW'
        $second | Should -Match 'NEW'
        $second | Should -Not -Match 'OLD'
        $second | Should -Match 'user-line'
        ([regex]::Matches($second, [regex]::Escape($script:ZshBlockStart))).Count | Should -Be 1
    }
    It 'does not corrupt bodies containing $ variables' {
        $r = Set-ZshManagedBlock -Content '' -Body '$env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"'
        $r | Should -Match ([regex]::Escape('$env:STARSHIP_CONFIG'))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed"`
Expected: the new `Resolve-ZshFeatures`, `Get-ZshProfileBody`, and `Set-ZshManagedBlock` describes FAIL (functions not defined). Task 2's tests still pass.

- [ ] **Step 3: Implement the three functions**

In `install.ps1`, insert these functions after `Get-ZshPackageManager` and before the entrypoint block:

```powershell
function Resolve-ZshFeatures {
    param([hashtable]$Params = @{}, [hashtable]$Available = @{})
    $autosuggest = (-not $Params.NoAutosuggestions) -and [bool]$Available.PSReadLinePrediction
    return @{
        Autosuggestions    = $autosuggest
        PredictionListView = $autosuggest -and [bool]$Available.PSReadLineListView
        PSFzf              = (-not $Params.NoPSFzf)   -and [bool]$Available.PSFzf
        PoshGit            = (-not $Params.NoPoshGit) -and [bool]$Available.PoshGit
    }
}

function Get-ZshProfileBody {
    param([hashtable]$Features = @{})
    $lines = @(
        '$env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"'
        'Invoke-Expression (&starship init powershell)'
    )
    if ($Features.Autosuggestions) {
        $lines += 'Set-PSReadLineOption -PredictionSource History'
        if ($Features.PredictionListView) {
            $lines += 'Set-PSReadLineOption -PredictionViewStyle ListView'
        }
    }
    if ($Features.PSFzf) {
        $lines += 'Import-Module PSFzf'
        $lines += "Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'"
    }
    if ($Features.PoshGit) {
        $lines += 'Import-Module posh-git'
    }
    return ($lines -join "`n")
}

function Set-ZshManagedBlock {
    param(
        [string]$Content = '',
        [Parameter(Mandatory)][string]$Body
    )
    $block = "$script:ZshBlockStart`n$Body`n$script:ZshBlockEnd"
    $pattern = [regex]::Escape($script:ZshBlockStart) + '.*?' + [regex]::Escape($script:ZshBlockEnd)
    $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($rx.IsMatch($Content)) {
        # MatchEvaluator avoids $-substitution corrupting the body.
        return $rx.Replace($Content, { param($m) $block })
    }
    $trimmed = $Content.TrimEnd("`r", "`n")
    if ($trimmed.Length -eq 0) { return "$block`n" }
    return "$trimmed`n`n$block`n"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed"`
Expected: all describes PASS (Task 2 + Task 3).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 windows/Windows.Tests.ps1
git commit -m "feat(windows): feature resolution and idempotent profile-block merge"
```

---

### Task 4: Install actions + orchestrator (`Invoke-ZshWindowsInstall`)

Adds the side-effectful pieces (binary/module install, config delivery, profile write, clink init) and the orchestrator that wires everything and prints a per-feature summary. Side effects are verified end-to-end by CI (Task 5); a pure availability-probe helper is unit-tested here.

**Files:**
- Modify: `install.ps1`
- Test: `windows/Windows.Tests.ps1`

**Interfaces:**
- Consumes: `Get-ZshPackageManager`, `Resolve-ZshFeatures`, `Get-ZshProfileBody`, `Set-ZshManagedBlock`, `$script:WingetIds`.
- Produces:
  - `Install-ZshBinary -Manager <string> -Name <string>` (side effect).
  - `Install-ZshModule -Name <string>` → bool (installed/available).
  - `Get-ZshModuleAvailability` → hashtable `@{ PSReadLinePrediction; PSReadLineListView; PSFzf; PoshGit }`.
  - `Get-ZshStarshipConfig -Destination <string> [-Force]` (copy from checkout or download).
  - `Write-ZshClinkInit` (writes clink lua).
  - `Invoke-ZshWindowsInstall` (orchestrator, accepts the same params as the script).

- [ ] **Step 1: Write the failing test for the availability probe**

Append to `windows/Windows.Tests.ps1`:

```powershell
Describe 'Get-ZshModuleAvailability' {
    It 'reports ListView available for PSReadLine >= 2.2' {
        Mock Get-Module {
            [pscustomobject]@{ Name = 'PSReadLine'; Version = [version]'2.3.4' }
        } -ParameterFilter { $Name -eq 'PSReadLine' }
        Mock Get-Module { $null } -ParameterFilter { $Name -in @('PSFzf', 'posh-git') }
        $a = Get-ZshModuleAvailability
        $a.PSReadLinePrediction | Should -BeTrue
        $a.PSReadLineListView   | Should -BeTrue
        $a.PSFzf                | Should -BeFalse
    }

    It 'reports prediction but not ListView for PSReadLine 2.1.x' {
        Mock Get-Module {
            [pscustomobject]@{ Name = 'PSReadLine'; Version = [version]'2.1.0' }
        } -ParameterFilter { $Name -eq 'PSReadLine' }
        Mock Get-Module { $null } -ParameterFilter { $Name -in @('PSFzf', 'posh-git') }
        $a = Get-ZshModuleAvailability
        $a.PSReadLinePrediction | Should -BeTrue
        $a.PSReadLineListView   | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -c "Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed"`
Expected: the `Get-ZshModuleAvailability` describe FAILS (function not defined). Others pass.

- [ ] **Step 3: Implement the install actions and orchestrator**

In `install.ps1`, add these functions after `Set-ZshManagedBlock` and before the entrypoint:

```powershell
function Install-ZshBinary {
    param([Parameter(Mandatory)][string]$Manager, [Parameter(Mandatory)][string]$Name)
    switch ($Manager) {
        'winget' { winget install --id $script:WingetIds[$Name] -e --source winget --accept-source-agreements --accept-package-agreements --silent }
        'scoop'  { scoop install $Name }
        'choco'  { choco install $Name -y }
    }
}

function Install-ZshModule {
    param([Parameter(Mandatory)][string]$Name)
    if (Get-Module -ListAvailable -Name $Name) { return $true }
    try {
        Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Failed to install module ${Name}: $($_.Exception.Message)"
        return $false
    }
}

function Get-ZshModuleAvailability {
    $prl = Get-Module -ListAvailable -Name PSReadLine |
        Sort-Object Version -Descending | Select-Object -First 1
    return @{
        PSReadLinePrediction = [bool]($prl -and $prl.Version -ge [version]'2.1.0')
        PSReadLineListView   = [bool]($prl -and $prl.Version -ge [version]'2.2.0')
        PSFzf                = [bool](Get-Module -ListAvailable -Name PSFzf)
        PoshGit              = [bool](Get-Module -ListAvailable -Name posh-git)
    }
}

function Get-ZshStarshipConfig {
    param([Parameter(Mandatory)][string]$Destination, [switch]$Force)
    if ((Test-Path $Destination) -and -not $Force) { return }
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $local = Join-Path $PSScriptRoot 'windows/starship.toml'
    if (Test-Path $local) {
        Copy-Item $local $Destination -Force
    } else {
        $url = 'https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/windows/starship.toml'
        Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing
    }
}

function Write-ZshClinkInit {
    $clinkDir = Join-Path $env:LOCALAPPDATA 'clink'
    if (-not (Test-Path $clinkDir)) { New-Item -ItemType Directory -Path $clinkDir -Force | Out-Null }
    'load(io.popen(''starship init cmd''):read("*a"))()' |
        Set-Content -Path (Join-Path $clinkDir 'starship.lua') -Encoding ASCII
}

function Invoke-ZshWindowsInstall {
    [CmdletBinding()]
    param(
        [switch]$NoCmd, [switch]$NoAutosuggestions, [switch]$NoPSFzf,
        [switch]$NoPoshGit, [switch]$Force, [string]$PackageManager
    )
    $summary = [ordered]@{}

    $pm = Get-ZshPackageManager -Prefer $PackageManager
    if (-not $pm) {
        Write-Error @'
No supported package manager found. Install one of:
  winget : https://learn.microsoft.com/windows/package-manager/winget/
  scoop  : https://scoop.sh/
  choco  : https://chocolatey.org/install
Then re-run install.ps1.
'@
        exit 1
    }
    Write-Host "Using package manager: $pm"

    Install-ZshBinary -Manager $pm -Name 'starship'; $summary['starship prompt'] = 'installed'
    Install-ZshBinary -Manager $pm -Name 'fzf';      $summary['fzf'] = 'installed'
    if (-not $NoCmd) {
        Install-ZshBinary -Manager $pm -Name 'clink'
        Write-ZshClinkInit
        $summary['cmd.exe prompt (clink)'] = 'installed'
    } else {
        $summary['cmd.exe prompt (clink)'] = 'skipped (-NoCmd)'
    }

    if (-not $NoPSFzf)   { $summary['PSFzf']    = if (Install-ZshModule 'PSFzf')    { 'installed' } else { 'skipped (install failed)' } }
    if (-not $NoPoshGit) { $summary['posh-git'] = if (Install-ZshModule 'posh-git') { 'installed' } else { 'skipped (install failed)' } }

    Get-ZshStarshipConfig -Destination (Join-Path $HOME '.config/starship.toml') -Force:$Force

    $available = Get-ZshModuleAvailability
    $features = Resolve-ZshFeatures -Params @{
        NoAutosuggestions = [bool]$NoAutosuggestions
        NoPSFzf           = [bool]$NoPSFzf
        NoPoshGit         = [bool]$NoPoshGit
    } -Available $available
    $summary['autosuggestions'] = if ($features.Autosuggestions) { 'enabled' } else { 'skipped (flag or PSReadLine too old)' }

    $body = Get-ZshProfileBody -Features $features
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    $existing = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
    Set-ZshManagedBlock -Content $existing -Body $body | Set-Content -Path $profilePath -Encoding UTF8

    Write-Host "`nSummary:"
    foreach ($k in $summary.Keys) { Write-Host ("  {0,-24} {1}" -f $k, $summary[$k]) }
    Write-Host "`nFinished! Restart your shell (and cmd.exe) to load the new prompt."
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed"`
Expected: all describes PASS, including `Get-ZshModuleAvailability`.

- [ ] **Step 5: Verify the script parses and loads cleanly**

Run: `pwsh -c "\$env:ZSH_INSTALL_NO_RUN='1'; . ./install.ps1; Get-Command Invoke-ZshWindowsInstall | Select-Object Name"`
Expected: prints `Invoke-ZshWindowsInstall`, no parse errors.

- [ ] **Step 6: Commit**

```bash
git add install.ps1 windows/Windows.Tests.ps1
git commit -m "feat(windows): install actions and orchestrator for install.ps1"
```

---

### Task 5: CI — Windows end-to-end job + Linux checks (Pester + drift)

Adds a GitHub Actions workflow: a `windows-latest` job that runs `install.ps1` for real and asserts the outcome, and an `ubuntu-latest` job that runs the Pester suite (via installed pwsh) and the Python drift/render tests.

**Files:**
- Create: `.github/workflows/windows.yml`

**Interfaces:**
- Consumes: `install.ps1`, `windows/Windows.Tests.ps1`, `windows/test_render_starship_config.py`, `windows/requirements-dev.txt`, `windows/starship.toml`.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/windows.yml`:

```yaml
name: windows

on:
  push:
    paths:
      - 'install.ps1'
      - 'windows/**'
      - 'templates/starship.toml.j2'
      - 'defaults/main.yml'
      - '.github/workflows/windows.yml'
  pull_request:
    paths:
      - 'install.ps1'
      - 'windows/**'
      - 'templates/starship.toml.j2'
      - 'defaults/main.yml'
      - '.github/workflows/windows.yml'

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Install Python deps
        run: pip install -r windows/requirements-dev.txt
      - name: Render/drift tests
        run: pytest windows/test_render_starship_config.py -v
      - name: Pester tests
        shell: pwsh
        run: |
          Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
          Invoke-Pester windows/Windows.Tests.ps1 -Output Detailed -CI

  windows-e2e:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run install.ps1
        shell: pwsh
        run: ./install.ps1 -NoCmd
      - name: Assert starship installed
        shell: pwsh
        run: starship --version
      - name: Assert config delivered
        shell: pwsh
        run: Test-Path "$HOME/.config/starship.toml" | Should-BeTrue -ErrorAction Stop
      - name: Assert managed block present in profile
        shell: pwsh
        run: |
          $content = Get-Content $PROFILE.CurrentUserAllHosts -Raw
          if ($content -notmatch [regex]::Escape('# >>> viasite-ansible zsh >>>')) {
            throw 'managed block missing from profile'
          }
      - name: Re-run is idempotent (single block)
        shell: pwsh
        run: |
          ./install.ps1 -NoCmd
          $content = Get-Content $PROFILE.CurrentUserAllHosts -Raw
          $count = ([regex]::Matches($content, [regex]::Escape('# >>> viasite-ansible zsh >>>'))).Count
          if ($count -ne 1) { throw "expected 1 managed block, found $count" }
```

Note: `-NoCmd` is used in CI because clink/cmd cannot be exercised on a headless runner; the clink lua write is covered by the code path and manual testing.

- [ ] **Step 2: Validate the workflow YAML locally**

Run: `.venv/bin/python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/windows.yml')); print('yaml ok')"`
Expected: `yaml ok`.

- [ ] **Step 3: Commit and push to trigger CI**

```bash
git add .github/workflows/windows.yml
git commit -m "ci(windows): e2e install job plus Pester and drift checks"
git push
```

- [ ] **Step 4: Verify CI is green**

Run: `gh run list --workflow=windows.yml --limit 1`
Expected: the latest run for this branch shows `completed  success` for both `checks` and `windows-e2e`. If red, open logs with `gh run view --log-failed` and fix before proceeding.

---

### Task 6: README — Windows section

Documents the Windows install path: the one-liner, the flags, the ExecutionPolicy note, and the feature-mapping table (so users understand completion bundles are not ported).

**Files:**
- Modify: `README.md` (insert a new section after the "Zero-knowledge install" section, before "Includes:")

**Interfaces:** none (docs only).

- [ ] **Step 1: Add the Windows section**

In `README.md`, immediately after the zero-knowledge install block (the line `> The previous \`install-macos.sh\` URL still works — it now forwards to \`install.sh\`.`) and before `## Includes:`, insert:

````markdown
## Windows (PowerShell / cmd)

zsh does not run in native Windows shells, so on Windows this repo installs the
**portable** parts of the setup — the starship prompt plus a fzf / autosuggestion
/ history experience — into PowerShell (and the starship prompt into `cmd.exe`
via [clink](https://chrisant996.github.io/clink/)). It uses a standalone
`install.ps1`; no Ansible, Python, or WSL.

Requires a preinstalled package manager: **winget**, **scoop**, or **choco**.

```powershell
irm https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/install.ps1 | iex
```

If your ExecutionPolicy blocks it, run PowerShell once as:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/install.ps1 | iex"
```

To pass flags, download-and-invoke instead of piping:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/install.ps1))) -NoCmd -NoPoshGit
```

### Flags

| Flag | Effect |
|---|---|
| `-NoCmd` | Skip clink install and cmd.exe prompt setup |
| `-NoAutosuggestions` | Skip PSReadLine history predictions |
| `-NoPSFzf` | Skip PSFzf (fzf `Ctrl+R` / `Ctrl+T`) |
| `-NoPoshGit` | Skip posh-git |
| `-Force` | Overwrite an existing `~/.config/starship.toml` |
| `-PackageManager <winget\|scoop\|choco>` | Force a specific manager |

### What maps over

| zsh feature | Windows equivalent |
|---|---|
| starship prompt | starship (PowerShell + cmd via clink) |
| zsh-autosuggestions | PSReadLine `-PredictionSource History` |
| fast-syntax-highlighting | PSReadLine built-in token coloring |
| fzf widgets / `Ctrl+R` | fzf + PSFzf |
| git/docker/kubectl completions | posh-git + native completers |
| ~25 antigen completion bundles | not ported (PowerShell has its own completion model) |

The Windows starship prompt is generated from the same template as the
Linux/macOS default (`windows/starship.toml`, kept in sync by CI).
````

- [ ] **Step 2: Verify the section renders and links are intact**

Run: `grep -n "## Windows (PowerShell / cmd)" README.md`
Expected: prints the heading line once.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Windows PowerShell/cmd install section"
```

---

## Self-Review

**Spec coverage:**
- Standalone `install.ps1`, no Ansible → Tasks 2–4. ✓
- Target shells PowerShell + cmd (clink) → PowerShell profile (Task 4), clink lua (Task 4 `Write-ZshClinkInit`, README Task 6). ✓
- Package managers auto-detect winget→scoop→choco, require one, fail if none → Task 2 `Get-ZshPackageManager`, Task 4 orchestrator error path. ✓
- Curated feature set + on/off flags; unsupported bundles not ported → Task 3 `Resolve-ZshFeatures`/`Get-ZshProfileBody`, README table Task 6. ✓
- Pre-rendered static starship.toml → Task 1. ✓
- Managed profile block with markers, idempotent → Task 3 `Set-ZshManagedBlock`, CI idempotency assertion Task 5. ✓
- Error handling (no PM, module failure, old PSReadLine, ExecutionPolicy) → Task 4 orchestrator + `Install-ZshModule` + `Resolve-ZshFeatures` floors; ExecutionPolicy documented Task 6. ✓
- Testing: Pester profile-merge + windows-latest E2E + drift check → Tasks 1 and 5. ✓
- Docs Windows section → Task 6. ✓

**Placeholder scan:** No TBD/TODO; every code and test step contains complete content. ✓

**Type consistency:** Function names and signatures are consistent across tasks — `Get-ZshPackageManager` (Task 2, used Task 4), `Resolve-ZshFeatures`/`Get-ZshProfileBody`/`Set-ZshManagedBlock` (Task 3, used Task 4), `Get-ZshModuleAvailability` returns the exact keys `Resolve-ZshFeatures` reads (`PSReadLinePrediction`, `PSReadLineListView`, `PSFzf`, `PoshGit`). The feature hashtable keys (`Autosuggestions`, `PredictionListView`, `PSFzf`, `PoshGit`) match between producer and consumer. ✓
