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
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'windows/starship.toml' } else { $null }
    if ($local -and (Test-Path $local)) {
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
        Write-ZshClinkInit
        $summary['cmd.exe prompt (clink)'] = if ($clinkOk) { 'installed' } else { 'failed' }
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
