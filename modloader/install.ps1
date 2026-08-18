$ErrorActionPreference = 'Stop'

$serverUrl = 'https://raw.githubusercontent.com/AroPix/TMFLiveReplay/refs/heads/master/modloader/'
$registryKey = 'HKCU:\Software\TMLoader'

function Wait-ForExit {
    if ($Host.Name -eq 'ConsoleHost') {
        Write-Host ''
        Read-Host 'Press Enter to close'
    }
}

function Get-TMLoaderPath {
    if (-not (Test-Path $registryKey)) {
        throw "Registry key '$registryKey' was not found."
    }

    $key = Get-Item -Path $registryKey
    $properties = Get-ItemProperty -Path $registryKey

    foreach ($name in @('Path', 'path', 'InstallPath', 'Directory')) {
        $value = $properties.PSObject.Properties[$name]
        if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value.Value)) {
            return [string]$value.Value
        }
    }

    $defaultValue = $key.GetValue('')
    if (-not [string]::IsNullOrWhiteSpace([string]$defaultValue)) {
        return [string]$defaultValue
    }

    $userValues = $properties.PSObject.Properties |
        Where-Object {
            $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' -and
            -not [string]::IsNullOrWhiteSpace([string]$_.Value)
        }

    if ($userValues.Count -eq 1) {
        return [string]$userValues[0].Value
    }

    throw "Could not determine the TMLoader path from '$registryKey'."
}

function Add-ServerToConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $content = Get-Content -Path $ConfigPath -Raw
    if ($content -match [regex]::Escape($Url)) {
        return $false
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [string[]](Get-Content -Path $ConfigPath)) {
        [void]$lines.Add($line)
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^(?<indent>[ \t]*)servers:\s*(?<rest>.*)$') {
            $indent = $matches['indent']
            $rest = $matches['rest'].Trim()
            $itemIndent = $indent + '  '

            if ($rest -eq '[]') {
                $lines[$i] = "${indent}servers:"
                $lines.Insert($i + 1, "$itemIndent- $Url")
                Set-Content -Path $ConfigPath -Value $lines
                return $true
            }

            $insertAt = $i + 1
            while ($insertAt -lt $lines.Count) {
                $current = $lines[$insertAt]

                if ([string]::IsNullOrWhiteSpace($current) -or $current.TrimStart().StartsWith('#')) {
                    $insertAt++
                    continue
                }

                $currentIndentLength = ($current.Length - $current.TrimStart().Length)
                $currentIndent = if ($currentIndentLength -gt 0) { $current.Substring(0, $currentIndentLength) } else { '' }

                if ($currentIndent.Length -le $indent.Length -and $current -match '^[ \t]*[^#\-][^:]*:') {
                    break
                }

                $insertAt++
            }

            $lines.Insert($insertAt, "$itemIndent- $Url")
            Set-Content -Path $ConfigPath -Value $lines
            return $true
        }
    }

    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        [void]$lines.Add('')
    }

    [void]$lines.Add('servers:')
    [void]$lines.Add("  - $Url")
    Set-Content -Path $ConfigPath -Value $lines
    return $true
}

try {
    $tmLoaderPath = Get-TMLoaderPath
    $configPath = Join-Path -Path $tmLoaderPath -ChildPath 'config.yaml'

    if (-not (Test-Path $configPath)) {
        throw "Config file '$configPath' was not found."
    }

    $wasInstalled = -not (Add-ServerToConfig -ConfigPath $configPath -Url $serverUrl)
    if ($wasInstalled) {
        Write-Host 'TMFLiveReplay is already installed in TMLoader.'
        Wait-ForExit
        exit 0
    }

    $process = Get-Process -Name 'TMLoader' -ErrorAction SilentlyContinue
    if ($process) {
        $process | Stop-Process -Force
        Write-Host 'TMFLiveReplay installed! TMLoader was closed, reopen it so TMFLiveReplay gets fetched!'
    }
    else {
        Write-Host 'TMFLiveReplay installed! Open TMLoader so it gets fetched!'
    }

    Wait-ForExit
}
catch {
    Write-Error $_
    Wait-ForExit
    exit 1
}
