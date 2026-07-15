Describe 'Get-ZshPackageManager' {
    BeforeAll {
        $env:ZSH_INSTALL_NO_RUN = '1'
        . "$PSScriptRoot/../install.ps1"
    }

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
