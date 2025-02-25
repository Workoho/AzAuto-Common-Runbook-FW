<#PSScriptInfo
.VERSION 1.0.1
.GUID 178d9772-9efb-4760-83c3-a40f58ff6d53
.AUTHOR Julian Pawlowski
.COMPANYNAME Workoho GmbH
.COPYRIGHT © 2024 Workoho GmbH
.TAGS
.LICENSEURI https://github.com/workoho/AzAuto-Common-Runbook-FW/LICENSE.txt
.PROJECTURI https://github.com/workoho/AzAuto-Common-Runbook-FW
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
    Version 1.0.1 (2024-11-04)
    - Fix PowerShell 5.1 compatibility.
#>

<#
.SYNOPSIS
    Read configuration file and generate hashtable.

.DESCRIPTION
    Read configuration file and generate hashtable.

.PARAMETER ConfigDir
    The directory where the configuration file is located.
    This is optional as otherwise, it is assumed that the configuration file is located in the 'config' subdirectory of the project directory.

.PARAMETER ConfigName
    The name of the configuration file.
    This is optional as otherwise, it is assumed that the configuration file is named 'AzAutoFWProject.psd1' when run from within a project directory.
    When this is run from within the framework directory, it is assumed that the configuration file is named 'AzAutoFW.psd1'.

.PARAMETER ProjectConfig
    Optional hashtable with the project configuration that was previously read already.
    For example, when you would like to read other configuration files afterwards.
#>

[CmdletBinding()]
param(
    [string]$ConfigDir,
    [string]$ConfigName,
    [hashtable]$ProjectConfig
)

Write-Verbose "---START of $((Get-Item $PSCommandPath).Name), $((Test-ScriptFileInfo $PSCommandPath | Select-Object -Property Version, Guid | & { process{$_.PSObject.Properties | & { process{$_.Name + ': ' + $_.Value} }} }) -join ', ') ---"

$projectDir = $null
$isAzAutoFWProject = $false

if ($ProjectConfig) {
    if (-not $ProjectConfig.Project.Directory) { Throw 'ProjectConfig.Project.Directory is missing.' }
    $projectDir = $ProjectConfig.Project.Directory
    if ($ProjectConfig.IsAzAutoFWProject) { $isAzAutoFWProject = $true }
}
else {
    $scriptPath = $MyInvocation.PSScriptRoot
    if (-not $scriptPath) { $scriptPath = Split-Path $MyInvocation.MyCommand.Path }
    $projectDir = Split-Path (Split-Path $scriptPath -Parent) -Parent
}

Write-Verbose "Project directory: $projectDir"

if (-not $ConfigDir -and -not $ConfigName) {
    $defaultConfigPath = Join-Path $projectDir (Join-Path 'config' 'AzAutoFW.psd1')
    $fallbackConfigPath = Join-Path $projectDir (Join-Path 'config' (Join-Path 'AzAutoFWProject' 'AzAutoFWProject.psd1'))
    if (Test-Path -Path $defaultConfigPath) {
        $configDir = Join-Path $projectDir 'config'
        $configName = 'AzAutoFW.psd1'
    }
    elseif (Test-Path -Path $fallbackConfigPath) {
        $configDir = Join-Path $projectDir (Join-Path 'config' 'AzAutoFWProject')
        $configName = 'AzAutoFWProject.psd1'
        $isAzAutoFWProject = $true
    }
}
else {
    $configDir = if ($ConfigDir) { if ($ConfigDir -match '^[A-Za-z]:\\|^/') { $ConfigDir } else { Join-Path $projectDir $ConfigDir } } else { Join-Path $projectDir 'config' }
    $configName = if ($ConfigName) { $ConfigName } else { 'AzAutoFW.psd1' }
    $isAzAutoFWProject = ($configName -eq 'AzAutoFWProject.psd1')
}
$configPath = Join-Path $configDir $configName
$config = $null
try {
    if ([System.IO.Path]::GetExtension((Split-Path -Path $configPath -Leaf)) -eq '.psd1') {
        $config = Import-PowerShellDataFile -Path $configPath -ErrorAction Stop | & {
            process {
                $newConfig = @{}
                $_.GetEnumerator() | & {
                    process {
                        if ($_.Key -in ('ModuleVersion', 'Author', 'Description')) {
                            $newConfig[$_.Key] = $_.Value
                        }
                    }
                }
                if ($_.PrivateData) {
                    $_.PrivateData.GetEnumerator() | & {
                        process {
                            if ($_.Key -eq 'PSData') { return }
                            $newConfig[$_.Key] = $_.Value
                        }
                    }
                }
                $newConfig
            }
        }
    }
    elseif ([System.IO.Path]::GetExtension((Split-Path -Path $configPath -Leaf)) -eq '.json') {
        $config = ConvertFrom-Json -Depth 3 -InputObject ((Get-Content -Path $configPath -Raw -ErrorAction Stop) -replace '/\*.*?\*/|//.*(?=[\r\n])')
    }
    else {
        Write-Error "Unknown configuration file type: $configPath" -ErrorAction Stop
        exit
    }
}
catch {
    Write-Error "Failed to read configuration file ${configPath}: $_" -ErrorAction Stop
    exit
}
$config.Project = @{ Directory = $projectDir }
$config.Config = @{ Directory = $configDir; Name = $configName; Path = $configPath }
if ($isAzAutoFWProject) {
    $config.IsAzAutoFWProject = $true
    $config.ParentProject = @{ Directory = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName (
            [IO.Path]::GetFileNameWithoutExtension((Split-Path $config.GitRepositoryUrl -Leaf))
        ).TrimEnd('.git')
    }
}

$localConfigName = ([System.Text.StringBuilder]::new()).Append(
    [System.IO.Path]::GetFileNameWithoutExtension($configName)
).Append(
    '.local'
).Append(
    ([System.IO.Path]::GetExtension((Split-Path -Path $configName -Leaf)))
).ToString()
$localConfigPath = Join-Path $configDir $localConfigName
try {
    try {
        # Check if the file is part of a Git repository
        if (& git ls-files --error-unmatch $localConfigPath 2>$null) {
            Write-Warning "Security warning: Local configuration file '$localConfigPath' should NOT be part of the Git repository."
        }
    }
    catch {
        # Ignore error
    }
    if ([System.IO.Path]::GetExtension((Split-Path -Path $localConfigPath -Leaf)) -eq '.psd1') {
        Write-Verbose "Trying to read local .psd1 configuration file: $localConfigPath"
        $config.Local = Import-PowerShellDataFile -Path $localConfigPath -ErrorAction Stop | & {
            process {
                $newConfig = @{}
                $_.GetEnumerator() | & {
                    process {
                        if ($_.Key -in ('Author', 'Description')) {
                            $newConfig[$_.Key] = $_.Value
                        }
                    }
                }
                if ($_.PrivateData) {
                    $_.PrivateData.GetEnumerator() | & {
                        process {
                            if ($_.Key -eq 'PSData') { return }
                            $newConfig[$_.Key] = $_.Value
                        }
                    }
                }
                $newConfig
            }
        }
    }
    elseif ([System.IO.Path]::GetExtension((Split-Path -Path $localConfigPath -Leaf)) -eq '.json') {
        Write-Verbose "Trying to read local .json configuration file: $localConfigPath"
        $config.Local = ConvertFrom-Json -Depth 3 -InputObject ((Get-Content -Path $localConfigPath -Raw -ErrorAction Stop) -replace '/\*.*?\*/|//.*(?=[\r\n])')
    }
    else {
        Write-Verbose "Unknown configuration file type: $localConfigPath" -ErrorAction Stop
        exit
    }
    Write-Verbose "Local configuration file added: $localConfigPath"
}
catch {
    Write-Verbose 'No local configuration file found.'
}

function Resolve-References {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$HashTable,

        [Parameter(Mandatory = $true)]
        [hashtable]$RootHashTable
    )

    $keys = @($HashTable.Keys)
    :outer foreach ($key in $keys) {
        $value = $HashTable[$key]

        if ($key -match '^(.+)ReferenceTo$') {
            $HashTable.Remove($key)
            $newKey = $matches[1]
            Write-Verbose "Found target for reference $key and created new key $newKey"

            if ($value -is [string] -and $value -match '^[^.]+\..+$') {
                $parts = $value.Split('.')
                $target = $RootHashTable
                foreach ($part in $parts) {
                    if ($part -match '^([^[]+)\[(\d+)\]$') {
                        $arrayName = $matches[1]
                        $index = [int]$matches[2]
                        if ($target.ContainsKey($arrayName) -and $target[$arrayName] -is [array] -and $index -lt $target[$arrayName].Length) {
                            $target = $target[$arrayName][$index]
                        }
                        else {
                            $HashTable[$newKey] = $null
                            Write-Error "Array reference '$part' not found in configuration"
                            continue outer
                        }
                    }
                    elseif ($target.ContainsKey($part)) {
                        $target = $target[$part]
                    }
                    else {
                        $HashTable[$newKey] = $null
                        Write-Error "Key reference '$part' not found in configuration"
                        continue outer
                    }
                }
                $HashTable[$newKey] = $target
            }
            elseif ($value -is [array]) {
                $newArray = [System.Collections.ArrayList]::new()
                foreach ($item in $value) {
                    if ($item -is [string] -and $item -match '^[^.]+\..+$') {
                        $parts = $item.Split('.')
                        $target = $RootHashTable
                        foreach ($part in $parts) {
                            if ($part -match '^([^[]+)\[(\d+)\]$') {
                                $arrayName = $matches[1]
                                $index = [int]$matches[2]
                                if ($target.ContainsKey($arrayName) -and $target[$arrayName] -is [array] -and $index -lt $target[$arrayName].Length) {
                                    $target = $target[$arrayName][$index]
                                }
                                else {
                                    Write-Error "Array reference '$part' not found in configuration"
                                    return
                                }
                            }
                            elseif ($target.ContainsKey($part)) {
                                $target = $target[$part]
                            }
                            else {
                                Write-Error "Key reference '$part' not found in configuration"
                                return
                            }
                        }
                        [void] $newArray.Add($target)
                    }
                }
                $HashTable[$key] = $newArray.ToArray()
            }
        }
        elseif ($value -is [hashtable]) {
            Resolve-References -HashTable $value -RootHashTable $RootHashTable
        }
        elseif ($value -is [array]) {
            foreach ($item in $value) {
                if ($item -is [hashtable]) {
                    Resolve-References -HashTable $item -RootHashTable $RootHashTable
                }
            }
        }
    }
}
Resolve-References -HashTable $config -RootHashTable $config

Write-Verbose "-----END of $((Get-Item $PSCommandPath).Name) ---"
return $config
