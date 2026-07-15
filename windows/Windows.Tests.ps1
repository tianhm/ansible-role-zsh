BeforeAll {
    $env:ZSH_INSTALL_NO_RUN = '1'
    . "$PSScriptRoot/../install.ps1"
}

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

    It 'returns winget when both winget and scoop are available' {
        Mock Get-Command { $true } -ParameterFilter { $Name -eq 'winget' }
        Mock Get-Command { $true } -ParameterFilter { $Name -eq 'scoop' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'choco' }
        Get-ZshPackageManager | Should -Be 'winget'
    }

    It 'returns $null when -Prefer manager is not available' {
        Mock Get-Command { $null }
        Get-ZshPackageManager -Prefer 'choco' | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-ZshFeatures' {
    BeforeEach {
        $allAvail = @{ PSReadLinePrediction = $true; PSReadLineListView = $true; PSFzf = $true; PoshGit = $true }
    }

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
        (Get-ZshProfileBody -Features @{ PSFzf = $true })  | Should -Match 'Set-PsFzfOption'
        (Get-ZshProfileBody -Features @{ PSFzf = $false }) | Should -Not -Match 'PSFzf'
    }
    It 'includes ListView line only when PredictionListView enabled' {
        (Get-ZshProfileBody -Features @{ Autosuggestions = $true; PredictionListView = $true })  | Should -Match 'ListView'
        (Get-ZshProfileBody -Features @{ Autosuggestions = $true; PredictionListView = $false }) | Should -Not -Match 'ListView'
    }
    It 'does not include PredictionSource when Autosuggestions disabled' {
        (Get-ZshProfileBody -Features @{ Autosuggestions = $false }) | Should -Not -Match 'PredictionSource'
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
    It 'does not corrupt bodies containing $ variables and .NET regex tokens' {
        $body = '$env:FOO = "$1 and $$ and $& literal"'
        $r = Set-ZshManagedBlock -Content '' -Body $body
        $r | Should -Match ([regex]::Escape('$1 and $$ and $& literal'))
    }
}

Describe 'Get-ZshModuleAvailability' {
    It 'reports ListView available for PSReadLine >= 2.2' {
        Mock Get-Module {
            [pscustomobject]@{ Name = 'PSReadLine'; Version = [version]'2.3.4' }
        } -ParameterFilter { $Name -eq 'PSReadLine' }
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'PSFzf' }
        Mock Get-Module { $true } -ParameterFilter { $Name -eq 'posh-git' }
        $a = Get-ZshModuleAvailability
        $a.PSReadLinePrediction | Should -BeTrue
        $a.PSReadLineListView   | Should -BeTrue
        $a.PSFzf                | Should -BeFalse
        $a.PoshGit              | Should -BeTrue
    }

    It 'reports prediction but not ListView for PSReadLine 2.1.x' {
        Mock Get-Module {
            [pscustomobject]@{ Name = 'PSReadLine'; Version = [version]'2.1.0' }
        } -ParameterFilter { $Name -eq 'PSReadLine' }
        Mock Get-Module { $null } -ParameterFilter { $Name -in @('PSFzf', 'posh-git') }
        $a = Get-ZshModuleAvailability
        $a.PSReadLinePrediction | Should -BeTrue
        $a.PSReadLineListView   | Should -BeFalse
        $a.PoshGit              | Should -BeFalse
    }

    It 'reports ListView available at exactly PSReadLine 2.2.0 (boundary is >=, not >)' {
        Mock Get-Module {
            [pscustomobject]@{ Name = 'PSReadLine'; Version = [version]'2.2.0' }
        } -ParameterFilter { $Name -eq 'PSReadLine' }
        Mock Get-Module { $null } -ParameterFilter { $Name -in @('PSFzf', 'posh-git') }
        $a = Get-ZshModuleAvailability
        $a.PSReadLineListView   | Should -BeTrue
    }
}
