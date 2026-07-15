[CmdletBinding()]
param(
    [switch]$NoCmd,
    [switch]$NoAutosuggestions,
    [switch]$NoPSFzf,
    [switch]$NoPoshGit,
    [switch]$Force,
    # NOTE: no [ValidateSet] here on purpose. When this script is run via
    # `irm ... | iex`, PowerShell initializes $PackageManager to '' and a
    # ValidateSet attribute rejects that empty default, breaking the primary
    # install path. The value is validated manually in Invoke-ZshWindowsInstall.
    [string]$PackageManager
)

Set-StrictMode -Version Latest

$script:ZshBlockStart = '# >>> viasite-ansible zsh >>>'
$script:ZshBlockEnd   = '# <<< viasite-ansible zsh <<<'
$script:WingetIds     = @{ starship = 'Starship.Starship'; fzf = 'junegunn.fzf'; clink = 'chrisant996.Clink' }

# Default starship.toml, embedded so `irm | iex` needs no second download
# (in remote mode $PSScriptRoot is empty and there is no local file to copy).
# Generated from templates/starship.toml.j2 by windows/render_starship_config.py;
# CI drift-checks that this matches windows/starship.toml. Do not edit by hand.
$script:StarshipToml = @'
# Managed by ansible-role-zsh (windows/render_starship_config.py) - do not edit
# Get editor completions based on the config schema
"$schema" = 'https://starship.rs/config-schema.json'

# Generated starship preset reproducing the role's powerlevel9k prompt layout.
# Colors/behavior are driven by the existing zsh_powerlevel9k_* role variables.
# add_newline = false

format = "$username$hostname$directory"
right_format = "$status$python$jobs$git_branch$git_commit$git_metrics$git_status$cmd_duration$time"

[username]
show_always = false
style_user = "fg:255 bg:024"
style_root = "fg:255 bg:124"
format = "[ ($user@)]($style)"

[hostname]
ssh_only = true
style = "fg:255 bg:024"
format = "[$hostname ]($style)"

[directory]
truncation_length = 3
truncate_to_repo = true
truncation_symbol = "…/"
style = "fg:255 bg:240"
format = "[ $path ]($style) "

[status]
disabled = false
map_symbol = true
style = "none"
format = "[$symbol$status]($style) "

[jobs]
style = "fg:000 bg:248"
format = "[ $symbol$number ]($style)"

[git_branch]
style = "fg:232 bg:100"
format = "[ $symbol$branch ]($style)"
ignore_branches = ['master', 'main']

[git_commit]
style = "fg:232 bg:100"
format = "[$tag ]($style)"

[git_metrics]
disabled = false

[git_status]
style = "fg:232 bg:094"
format = "([ $all_status$ahead_behind ]($style))"

[cmd_duration]
min_time = 3000
style = "fg:000 bg:248"
format = "[ $duration ]($style)"

[python]
format = '[${pyenv_prefix}($virtualenv)]($style) '

[time]
disabled = false
style = "fg:000 bg:248"
format = "[ $time ]($style)"
'@

function Get-ZshPackageManager {
    param([string]$Prefer)
    $order = if ($Prefer) { @($Prefer) } else { @('winget', 'scoop', 'choco') }
    foreach ($pm in $order) {
        if (Get-Command $pm -ErrorAction SilentlyContinue) { return $pm }
    }
    return $null
}

function Resolve-ZshFeatures {
    param([hashtable]$Params = @{}, [hashtable]$Available = @{})
    $autosuggest = (-not $Params['NoAutosuggestions']) -and [bool]$Available['PSReadLinePrediction']
    return @{
        Autosuggestions    = $autosuggest
        PredictionListView = $autosuggest -and [bool]$Available['PSReadLineListView']
        PSFzf              = (-not $Params['NoPSFzf'])   -and [bool]$Available['PSFzf']
        PoshGit            = (-not $Params['NoPoshGit']) -and [bool]$Available['PoshGit']
    }
}

function Get-ZshProfileBody {
    param([hashtable]$Features = @{})
    $lines = @(
        '$env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"'
        'Invoke-Expression (&starship init powershell)'
    )
    if ($Features['Autosuggestions']) {
        $lines += 'Set-PSReadLineOption -PredictionSource History'
        if ($Features['PredictionListView']) {
            $lines += 'Set-PSReadLineOption -PredictionViewStyle ListView'
        }
    }
    if ($Features['PSFzf']) {
        $lines += 'Import-Module PSFzf'
        $lines += "Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'"
    }
    if ($Features['PoshGit']) {
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

function Install-ZshBinary {
    param([Parameter(Mandatory)][string]$Manager, [Parameter(Mandatory)][string]$Name)
    switch ($Manager) {
        'winget' { winget install --id $script:WingetIds[$Name] -e --source winget --accept-source-agreements --accept-package-agreements --silent }
        'scoop'  { scoop install $Name }
        'choco'  { choco install $Name -y }
    }
    # $LASTEXITCODE is only set by native executables; if it's null (e.g. the
    # manager shimmed out to a function/cmdlet), fall back to $? as the
    # "no error occurred" signal.
    if ($null -eq $LASTEXITCODE) { return [bool]$? }
    return $LASTEXITCODE -eq 0
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
    # Write the embedded config directly (UTF-8, no BOM) so this works identically
    # in checkout mode and under `irm | iex`, with no network dependency.
    [System.IO.File]::WriteAllText($Destination, $script:StarshipToml + "`n")
}

function Write-ZshClinkInit {
    $clinkDir = Join-Path $env:LOCALAPPDATA 'clink'
    if (-not (Test-Path $clinkDir)) { New-Item -ItemType Directory -Path $clinkDir -Force | Out-Null }
    'load(io.popen(''starship init cmd''):read("*a"))()' |
        Set-Content -Path (Join-Path $clinkDir 'starship.lua') -Encoding ASCII
}

function Write-ZshClinkFzf {
    # Bind Ctrl+R in cmd.exe to fzf over clink's command history. Self-contained
    # clink Lua (our own, embedded — no third-party download). Requires fzf on
    # PATH (installed above). Auto-loaded by clink from its scripts dir.
    $clinkDir = Join-Path $env:LOCALAPPDATA 'clink'
    if (-not (Test-Path $clinkDir)) { New-Item -ItemType Directory -Path $clinkDir -Force | Out-Null }
    $lua = @'
-- viasite-ansible zsh: bind Ctrl+R to fzf over clink command history.
-- Self-contained (no third-party clink-fzf). Requires fzf on PATH.
-- Mirrors the clink-fzf mechanism: get history from the running clink session
-- (not a guessed file), pipe to fzf, strip the leading index from the choice.

local function fzf_history(rl_buffer)
    if not (clink and clink.getsession) then rl_buffer:refreshline(); return end
    local session = clink.getsession()
    if not session or session == "" then rl_buffer:refreshline(); return end
    local history = 'clink --session '..session..' history --time-format " "'
    local query = (rl_buffer:getbuffer() or ""):gsub('"', "")
    local cmd = '2>nul '..history..' | fzf --height 40% --reverse --tac --no-sort --exact --query "'..query..'"'
    local p = io.popen(cmd)
    if not p then rl_buffer:refreshline(); return end
    local str = p:read("*line")
    p:close()
    if str and str ~= "" then
        str = str:gsub("[\r\n]+$", "")     -- drop trailing CR/LF
        str = str:gsub("^%s*%d+%s+", "")   -- drop the leading history index
        rl_buffer:beginundogroup()
        rl_buffer:remove(0, -1)
        rl_buffer:insert(str)
        rl_buffer:endundogroup()
    end
    rl_buffer:refreshline()
end

_fzf_history = fzf_history
if rl and rl.setbinding then
    rl.setbinding([["\C-r"]], [["luafunc:_fzf_history"]])
end
'@
    [System.IO.File]::WriteAllText((Join-Path $clinkDir 'fzf-history.lua'), $lua + "`n")
    return $true
}

function Invoke-ZshWindowsInstall {
    [CmdletBinding()]
    param(
        [switch]$NoCmd, [switch]$NoAutosuggestions, [switch]$NoPSFzf,
        [switch]$NoPoshGit, [switch]$Force, [string]$PackageManager
    )
    if ($PackageManager -and $PackageManager -notin @('winget', 'scoop', 'choco')) {
        throw "Invalid -PackageManager '$PackageManager'. Valid values: winget, scoop, choco."
    }
    $summary = [ordered]@{}

    $pm = Get-ZshPackageManager -Prefer $PackageManager
    if (-not $pm) {
        throw @'
No supported package manager found. Install one of:
  winget : https://learn.microsoft.com/windows/package-manager/winget/
  scoop  : https://scoop.sh/
  choco  : https://chocolatey.org/install
Then re-run install.ps1.
'@
    }
    Write-Host "Using package manager: $pm"

    $starshipOk = Install-ZshBinary -Manager $pm -Name 'starship'
    $summary['starship prompt'] = if ($starshipOk) { 'installed' } else { 'failed' }
    $fzfOk = Install-ZshBinary -Manager $pm -Name 'fzf'
    $summary['fzf'] = if ($fzfOk) { 'installed' } else { 'failed' }
    if (-not $NoCmd) {
        $clinkOk = Install-ZshBinary -Manager $pm -Name 'clink'
        # Refresh PATH so the just-installed clink shim resolves in this session.
        $env:PATH = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')
        Write-ZshClinkInit
        $fzfCmdOk = Write-ZshClinkFzf
        # Register our script dir so clink loads starship.lua + fzf-history.lua
        # regardless of which profile directory clink was configured with.
        if (Get-Command clink -ErrorAction SilentlyContinue) {
            clink installscripts (Join-Path $env:LOCALAPPDATA 'clink') | Out-Null
        }
        $summary['cmd.exe prompt (clink)'] = if ($clinkOk) { 'installed' } else { 'failed' }
        $summary['cmd.exe fzf (Ctrl+R)'] = if ($fzfCmdOk) { 'installed' } else { 'skipped' }
    } else {
        $summary['cmd.exe prompt (clink)'] = 'skipped (-NoCmd)'
    }

    if (-not $NoPSFzf)   { $summary['PSFzf']    = if (Install-ZshModule 'PSFzf')    { 'installed' } else { 'skipped (install failed)' } }
    else                 { $summary['PSFzf']    = 'skipped (-NoPSFzf)' }
    if (-not $NoPoshGit) { $summary['posh-git'] = if (Install-ZshModule 'posh-git') { 'installed' } else { 'skipped (install failed)' } }
    else                 { $summary['posh-git'] = 'skipped (-NoPoshGit)' }

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

# ---- entrypoint (skipped when dot-sourced for tests) ----
# Pass params explicitly rather than splatting $PSBoundParameters: under
# `irm ... | iex` the script has no bound parameters, so the splat would be
# empty/undefined. The param-block variables are always defined here.
if (-not $env:ZSH_INSTALL_NO_RUN) {
    Invoke-ZshWindowsInstall -NoCmd:$NoCmd -NoAutosuggestions:$NoAutosuggestions `
        -NoPSFzf:$NoPSFzf -NoPoshGit:$NoPoshGit -Force:$Force -PackageManager $PackageManager
}
