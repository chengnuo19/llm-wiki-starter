[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [Parameter()]
    [string]$Name,

    [Parameter()]
    [string]$PluginSourcePath,

    [Parameter()]
    [switch]$SkipPlugins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$templateRoot = Join-Path $PSScriptRoot 'template'
if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
    throw "Template directory not found: $templateRoot"
}

$requiredTemplates = @(
    'AGENTS.md.tmpl',
    'CLAUDE.md.tmpl',
    'START-HERE.md.tmpl',
    'wiki\index.md.tmpl',
    'wiki\log.md.tmpl'
)

foreach ($relativePath in $requiredTemplates) {
    $templatePath = Join-Path $templateRoot $relativePath
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw "Required template not found: $templatePath"
    }
}

$targetPath = [System.IO.Path]::GetFullPath($Path)

if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    throw "Target path is a file, not a directory: $targetPath"
}

if (Test-Path -LiteralPath $targetPath -PathType Container) {
    $existingItem = Get-ChildItem -LiteralPath $targetPath -Force | Select-Object -First 1
    if ($null -ne $existingItem) {
        throw "Target directory is not empty. Choose a new or empty directory: $targetPath"
    }
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    $trimmedTarget = $targetPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $Name = [System.IO.Path]::GetFileName($trimmedTarget)
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    throw 'Could not infer the vault name. Pass -Name explicitly.'
}

$pluginPackages = @()
$quickAddPackage = $null
if (-not $SkipPlugins -and [string]::IsNullOrWhiteSpace($PluginSourcePath)) {
    throw 'Pass -PluginSourcePath or use -SkipPlugins to initialize without community plugins.'
}

if (-not $SkipPlugins) {
    $pluginSourceRoot = [System.IO.Path]::GetFullPath($PluginSourcePath)
    if (-not (Test-Path -LiteralPath $pluginSourceRoot -PathType Container)) {
        throw "Plugin source directory not found: $pluginSourceRoot. Pass -SkipPlugins to initialize without plugins."
    }

    $enabledPluginIds = @()
    $sourceObsidianDirectory = Split-Path -Parent $pluginSourceRoot
    $enabledPluginFile = Join-Path $sourceObsidianDirectory 'community-plugins.json'
    if (Test-Path -LiteralPath $enabledPluginFile -PathType Leaf) {
        $parsedEnabledPluginIds =
            [System.IO.File]::ReadAllText($enabledPluginFile) |
            ConvertFrom-Json
        $enabledPluginIds = @($parsedEnabledPluginIds)
    }

    foreach ($pluginDirectory in Get-ChildItem -LiteralPath $pluginSourceRoot -Directory) {
        $manifestPath = Join-Path $pluginDirectory.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-Warning "Skipping plugin without manifest.json: $($pluginDirectory.Name)"
            continue
        }

        try {
            $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        }
        catch {
            Write-Warning "Skipping plugin with invalid manifest.json: $($pluginDirectory.Name)"
            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$manifest.id)) {
            Write-Warning "Skipping plugin without a manifest id: $($pluginDirectory.Name)"
            continue
        }

        if (
            ($enabledPluginIds.Count -gt 0) -and
            ($enabledPluginIds -notcontains [string]$manifest.id)
        ) {
            continue
        }

        $pluginPackages += [pscustomobject]@{
            Directory = $pluginDirectory
            Id = [string]$manifest.id
            Name = [string]$manifest.name
            Version = [string]$manifest.version
        }
    }

    if ($pluginPackages.Count -eq 0) {
        throw "No enabled plugin packages with valid manifests were found in: $pluginSourceRoot"
    }

    if (@($pluginPackages | ForEach-Object { $_.Id }) -contains 'quickadd') {
        $sourceVaultRoot = Split-Path -Parent $sourceObsidianDirectory
        $quickAddPackageDirectory = Join-Path $sourceVaultRoot 'QuickAdd Packages'
        if (Test-Path -LiteralPath $quickAddPackageDirectory -PathType Container) {
            $quickAddPackage =
                Get-ChildItem -LiteralPath $quickAddPackageDirectory -File -Filter '*.quickadd.json' |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
        }

        if ($null -eq $quickAddPackage) {
            Write-Warning "QuickAdd is enabled, but no exported package was found in: $quickAddPackageDirectory"
        }
    }
}

if (-not $PSCmdlet.ShouldProcess($targetPath, "Initialize LLM Wiki '$Name'")) {
    return
}

New-Item -ItemType Directory -Force -Path $targetPath | Out-Null

$directories = @(
    'raw',
    'raw\assets',
    'wiki',
    'wiki\entities',
    'wiki\concepts',
    'wiki\sources',
    'wiki\analyses'
)

foreach ($relativePath in $directories) {
    New-Item -ItemType Directory -Force -Path (Join-Path $targetPath $relativePath) | Out-Null
}

$createdDate = Get-Date -Format 'yyyy-MM-dd'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
$templateFiles = Get-ChildItem -LiteralPath $templateRoot -Recurse -File

foreach ($templateFile in $templateFiles) {
    $relativePath = $templateFile.FullName.Substring($templateRoot.Length).TrimStart('\', '/')
    if ($relativePath.EndsWith('.tmpl', [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $relativePath.Substring(0, $relativePath.Length - '.tmpl'.Length)
    }
    $destinationPath = Join-Path $targetPath $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath

    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

    $content = [System.IO.File]::ReadAllText($templateFile.FullName)
    $content = $content.Replace('{{VAULT_NAME}}', $Name)
    $content = $content.Replace('{{DATE}}', $createdDate)
    [System.IO.File]::WriteAllText($destinationPath, $content, $utf8WithoutBom)
}

if (-not $SkipPlugins) {
    $targetPluginRoot = Join-Path $targetPath '.obsidian\plugins'
    New-Item -ItemType Directory -Force -Path $targetPluginRoot | Out-Null

    foreach ($pluginPackage in $pluginPackages) {
        $sourcePluginDirectory = $pluginPackage.Directory.FullName
        $targetPluginDirectory = Join-Path $targetPluginRoot $pluginPackage.Directory.Name

        foreach ($sourceFile in Get-ChildItem -LiteralPath $sourcePluginDirectory -Recurse -File) {
            $relativePluginPath = $sourceFile.FullName.Substring($sourcePluginDirectory.Length).TrimStart('\', '/')
            $pathSegments = $relativePluginPath -split '[\\/]'

            if ($sourceFile.Name -ieq 'data.json' -or $pathSegments -contains '.git') {
                continue
            }

            $targetFile = Join-Path $targetPluginDirectory $relativePluginPath
            $targetFileDirectory = Split-Path -Parent $targetFile
            New-Item -ItemType Directory -Force -Path $targetFileDirectory | Out-Null
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetFile
        }
    }

    $pluginIds = @($pluginPackages | ForEach-Object { $_.Id } | Sort-Object -Unique)
    $communityPluginsJson = ConvertTo-Json -InputObject $pluginIds
    $communityPluginsPath = Join-Path $targetPath '.obsidian\community-plugins.json'
    [System.IO.File]::WriteAllText(
        $communityPluginsPath,
        $communityPluginsJson + [Environment]::NewLine,
        $utf8WithoutBom
    )

    if ($null -ne $quickAddPackage) {
        $targetPackageDirectory = Join-Path $targetPath 'QuickAdd Packages'
        New-Item -ItemType Directory -Force -Path $targetPackageDirectory | Out-Null
        Copy-Item `
            -LiteralPath $quickAddPackage.FullName `
            -Destination (Join-Path $targetPackageDirectory 'LLM Wiki.quickadd.json')
    }
}

Write-Host ''
Write-Host "LLM Wiki initialized: $targetPath" -ForegroundColor Green
Write-Host 'Next steps:'
Write-Host '  1. Open this directory as a vault in Obsidian.'
Write-Host '  2. Set the attachment folder to raw/assets.'
Write-Host '  3. Read START-HERE.md.'
Write-Host '  4. Put the first source in raw/ and run an Ingest request.'
if (-not $SkipPlugins) {
    Write-Host "  5. Review and enable the $($pluginPackages.Count) copied community plugins in Obsidian."
    Write-Host '     Plugin settings and data.json files were intentionally not copied.'
    if ($null -ne $quickAddPackage) {
        Write-Host '  6. In QuickAdd settings, import QuickAdd Packages/LLM Wiki.quickadd.json.'
    }
}

[pscustomobject]@{
    Name = $Name
    Path = $targetPath
    Created = $createdDate
    Plugins = if ($SkipPlugins) { 0 } else { $pluginPackages.Count }
    QuickAddPackage = (-not $SkipPlugins -and $null -ne $quickAddPackage)
}
