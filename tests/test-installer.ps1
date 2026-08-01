[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-True {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $Condition) {
    throw "Assertion failed: $Message"
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot "scripts\install-codex-proxy-shortcut.ps1"
$fixtures = Join-Path $PSScriptRoot "fixtures"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-connectivity-test-" + [guid]::NewGuid().ToString("N"))
$originalCodexHome = $env:CODEX_HOME
$proxyNames = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")
$beforeUserProxy = @{}
$beforeMachineProxy = @{}

foreach ($name in $proxyNames) {
  $beforeUserProxy[$name] = [Environment]::GetEnvironmentVariable($name, "User")
  $beforeMachineProxy[$name] = [Environment]::GetEnvironmentVariable($name, "Machine")
}

try {
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

  foreach ($case in @("fresh", "legacy")) {
    $caseRoot = Join-Path $testRoot $case
    $codexHome = Join-Path $caseRoot ".codex"
    $launcherRoot = Join-Path $caseRoot "launchers"
    $shortcutDirectory = Join-Path $caseRoot "desktop"
    New-Item -ItemType Directory -Path $codexHome, $shortcutDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtures "$case-config.toml") -Destination (Join-Path $codexHome "config.toml")

    $sessionsDirectory = Join-Path $codexHome "sessions"
    New-Item -ItemType Directory -Path $sessionsDirectory -Force | Out-Null
    $sessionSentinel = Join-Path $sessionsDirectory "history-sentinel.jsonl"
    [IO.File]::WriteAllText($sessionSentinel, '{"history":"must-not-change"}')
    $sentinelHashBefore = (Get-FileHash -LiteralPath $sessionSentinel -Algorithm SHA256).Hash

    $env:CODEX_HOME = $codexHome
    $result = & $installer `
      -ProxyHost "127.0.0.1" `
      -ProxyPort 12450 `
      -ShortcutName "Codex-Test-$case" `
      -LauncherRoot $launcherRoot `
      -ShortcutDirectory $shortcutDirectory `
      -SkipProxyCheck

    $configPath = Join-Path $codexHome "config.toml"
    $config = [IO.File]::ReadAllText($configPath)
    $launcherPath = [string]$result.LauncherPath
    $launcher = [IO.File]::ReadAllText($launcherPath)

    Assert-True (Test-Path -LiteralPath ([string]$result.ShortcutPath)) "$case shortcut should exist"
    Assert-True ($launcher.Contains('WS_PROXY')) "$case launcher should set WS_PROXY"
    Assert-True ($launcher.Contains('WSS_PROXY')) "$case launcher should set WSS_PROXY"
    Assert-True ($launcher.Contains($codexHome.Replace("'", "''"))) "$case launcher should preserve CODEX_HOME"
    Assert-True ($launcher.Contains(([string]$result.ShortcutPath).Replace("'", "''"))) "$case launcher should know its shortcut path"
    Assert-True ($launcher.Contains('Sort-Object Version -Descending')) "$case launcher should select the newest AppX package"
    Assert-True ($launcher.Contains('$shortcut.IconLocation = $newIconLocation')) "$case launcher should self-refresh the versioned icon"
    Assert-True ([string]$result.AppUpdateBehavior -like '*self-refreshes*') "$case installer should report update-safe behavior"
    Assert-True (((Get-FileHash -LiteralPath $sessionSentinel -Algorithm SHA256).Hash) -eq $sentinelHashBefore) "$case history files should remain unchanged"

    if ($case -eq "fresh") {
      $fixture = [IO.File]::ReadAllText((Join-Path $fixtures "fresh-config.toml"))
      Assert-True ($config -ceq $fixture) "fresh installation should not change config.toml"
      Assert-True (-not [bool]$result.ConfigChanged) "fresh installation should report ConfigChanged=false"
      Assert-True (-not [bool]$result.LegacyProviderRestored) "fresh installation should not report a legacy repair"
    } else {
      Assert-True ($config.Contains('model_provider = "openai"')) "legacy installation should restore the openai provider"
      Assert-True (-not $config.Contains('model_provider = "codex_proxy_http"')) "legacy provider selection should be removed"
      Assert-True (-not $config.Contains('[model_providers.codex_proxy_http]')) "legacy provider table should be removed"
      Assert-True (-not $config.Contains('# BEGIN codex-proxy-shortcut managed provider')) "legacy managed marker should be removed"
      Assert-True ([bool]$result.ConfigChanged) "legacy installation should report ConfigChanged=true"
      Assert-True ([bool]$result.LegacyProviderRestored) "legacy installation should report a legacy repair"
      Assert-True (Test-Path -LiteralPath ([string]$result.ConfigBackup) -PathType Leaf) "legacy repair should create a config backup"
    }
  }

  foreach ($name in $proxyNames) {
    Assert-True ([Environment]::GetEnvironmentVariable($name, "User") -eq $beforeUserProxy[$name]) "User $name should not change"
    Assert-True ([Environment]::GetEnvironmentVariable($name, "Machine") -eq $beforeMachineProxy[$name]) "Machine $name should not change"
  }

  "Installer regression tests: PASS"
} finally {
  if ($null -eq $originalCodexHome) {
    Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
  } else {
    $env:CODEX_HOME = $originalCodexHome
  }

  $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
  if (
    (Test-Path -LiteralPath $resolvedTestRoot) -and
    $resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
    (Split-Path -Leaf $resolvedTestRoot).StartsWith("codex-connectivity-test-", [StringComparison]::Ordinal)
  ) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
  }
}
