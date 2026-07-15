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

# ---- entrypoint (skipped when dot-sourced for tests) ----
if (-not $env:ZSH_INSTALL_NO_RUN) {
    Invoke-ZshWindowsInstall @PSBoundParameters
}
