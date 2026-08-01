[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
  [Parameter()]
  [ValidatePattern("^[A-Za-z0-9.:-]+$")]
  [string]$ProxyHost = "127.0.0.1",

  [Parameter()]
  [ValidateRange(1, 65535)]
  [int]$ProxyPort = 12450,

  [Parameter()]
  [string]$ShortcutName,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$LauncherRoot = "D:\Codex\codex-proxy-shortcuts",

  [Parameter()]
  [string]$ShortcutDirectory = [Environment]::GetFolderPath("Desktop"),

  [Parameter()]
  [switch]$SkipProxyCheck,

  [Parameter()]
  [switch]$AllowNonLoopbackProxy
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw "This installer supports Windows only."
}

$loopbackHosts = @("127.0.0.1", "localhost", "::1")
if (-not $AllowNonLoopbackProxy -and $ProxyHost -notin $loopbackHosts) {
  throw "Refusing non-loopback proxy '$ProxyHost'. Use -AllowNonLoopbackProxy only after explicit user approval."
}

if ([string]::IsNullOrWhiteSpace($ShortcutName)) {
  $ShortcutName = "Codex-HTTP-Proxy-$ProxyPort"
}

foreach ($invalidCharacter in [IO.Path]::GetInvalidFileNameChars()) {
  if ($ShortcutName.Contains([string]$invalidCharacter)) {
    throw "ShortcutName contains an invalid filename character: $invalidCharacter"
  }
}

$proxyAuthority = if ($ProxyHost.Contains(":")) {
  "[$ProxyHost]:$ProxyPort"
} else {
  "${ProxyHost}:$ProxyPort"
}
$proxyUri = "http://$proxyAuthority"
$proxyId = ($ProxyHost -replace "[^A-Za-z0-9.-]", "_") + "-$ProxyPort"
$launcherDirectory = Join-Path $LauncherRoot $proxyId
$launcherPath = Join-Path $launcherDirectory "Launch-Codex-With-Proxy.ps1"
$shortcutPath = Join-Path $ShortcutDirectory "$ShortcutName.lnk"

if (-not $SkipProxyCheck) {
  $proxyListening = Test-NetConnection $ProxyHost -Port $ProxyPort -InformationLevel Quiet
  if (-not $proxyListening) {
    throw "The HTTP proxy is not listening at ${ProxyHost}:$ProxyPort. Start it first or use -SkipProxyCheck to create the files offline."
  }
}

$package = Get-AppxPackage -Name OpenAI.Codex |
  Sort-Object Version -Descending |
  Select-Object -First 1

if (-not $package) {
  throw "The OpenAI.Codex Store package is not installed."
}

$codexExe = Join-Path $package.InstallLocation "app\ChatGPT.exe"
if (-not (Test-Path -LiteralPath $codexExe)) {
  throw "ChatGPT.exe was not found at the expected package path: $codexExe"
}

$codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
  Join-Path $env:USERPROFILE ".codex"
} else {
  $env:CODEX_HOME
}
$configPath = Join-Path $codexHome "config.toml"

if (-not (Test-Path -LiteralPath $configPath)) {
  throw "Codex config was not found: $configPath"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$originalConfig = [IO.File]::ReadAllText($configPath)
$managedPattern = "(?ms)^# BEGIN codex-proxy-shortcut managed provider\r?\n.*?^# END codex-proxy-shortcut managed provider\r?\n?"
$legacyManagedProviderFound = [regex]::IsMatch($originalConfig, $managedPattern)
$updatedConfig = [regex]::Replace($originalConfig, $managedPattern, "")

# Older releases selected a custom codex_proxy_http provider to force HTTP/SSE.
# The app's default thread/list request filters by the active provider, so that
# selection made existing "openai" threads look missing. Preserve the built-in
# provider id and let the process-scoped proxy carry both HTTPS and WebSockets.
$legacyProviderSelectionPattern = '(?m)^(?<indent>\s*)model_provider\s*=\s*"codex_proxy_http"\s*$'
$firstTable = [regex]::Match($updatedConfig, "(?m)^\s*\[")
if ($firstTable.Success) {
  $topLevelPrefix = $updatedConfig.Substring(0, $firstTable.Index)
  $tableContent = $updatedConfig.Substring($firstTable.Index)
} else {
  $topLevelPrefix = $updatedConfig
  $tableContent = ""
}

$legacyProviderSelectionFound = [regex]::IsMatch(
  $topLevelPrefix,
  $legacyProviderSelectionPattern
)
if ($legacyProviderSelectionFound) {
  $topLevelPrefix = [regex]::Replace(
    $topLevelPrefix,
    $legacyProviderSelectionPattern,
    '${indent}model_provider = "openai"',
    1
  )
}
$updatedConfig = $topLevelPrefix + $tableContent
$legacyProviderRestored = $legacyManagedProviderFound -or $legacyProviderSelectionFound

$launcherTemplate = @'
param()

$ErrorActionPreference = "Stop"

# These variables exist only in this launcher and the Codex processes it starts.
# This script does not change User/Machine environment variables or Windows proxy settings.
$proxy = "__PROXY_URI__"
$proxyHost = "__PROXY_HOST__"
$proxyPort = __PROXY_PORT__
$noProxy = "localhost,127.0.0.1,::1,.local"
$shortcutPath = '__SHORTCUT_PATH__'

# Pin the launcher to the same Codex home inspected during installation so the
# normal shortcut and proxy shortcut see the same local task history.
$env:CODEX_HOME = '__CODEX_HOME__'

if (Get-Process -Name ChatGPT -ErrorAction SilentlyContinue) {
  throw "Codex/ChatGPT is already running. Quit it completely before using this shortcut."
}

if (-not (Test-NetConnection $proxyHost -Port $proxyPort -InformationLevel Quiet)) {
  throw "Codex was not started because the local HTTP proxy is not listening at ${proxyHost}:$proxyPort."
}

$package = Get-AppxPackage -Name OpenAI.Codex |
  Sort-Object Version -Descending |
  Select-Object -First 1

if (-not $package) {
  throw "The OpenAI.Codex Store package is not installed."
}

$codexExe = Join-Path $package.InstallLocation "app\ChatGPT.exe"
if (-not (Test-Path -LiteralPath $codexExe)) {
  throw "ChatGPT.exe was not found at: $codexExe"
}

# Store updates replace the versioned WindowsApps directory. Refresh only the
# shortcut icon after resolving the newest package; the shortcut continues to
# target this stable launcher and needs no manual recreation after an update.
if (Test-Path -LiteralPath $shortcutPath) {
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $newIconLocation = "$codexExe,0"
    if ($shortcut.IconLocation -ne $newIconLocation) {
      $shortcut.IconLocation = $newIconLocation
      $shortcut.Save()
    }
  } catch {
    Write-Warning "Codex will still start, but the shortcut icon could not be refreshed: $($_.Exception.Message)"
  }
}

$proxyVariables = @(
  "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
  "http_proxy", "https_proxy", "all_proxy",
  "WS_PROXY", "WSS_PROXY", "ws_proxy", "wss_proxy"
)
foreach ($name in $proxyVariables) {
  Set-Item -LiteralPath "Env:$name" -Value $proxy
}
$env:NO_PROXY = $noProxy
$env:no_proxy = $noProxy

Start-Process -FilePath $codexExe `
  -WorkingDirectory (Split-Path -Parent $codexExe) `
  -ArgumentList @(
    "--proxy-server=$proxy",
    "--proxy-bypass-list=localhost;127.0.0.1;::1",
    "--disable-quic"
)
'@

$escapedCodexHome = $codexHome.Replace("'", "''")
$escapedShortcutPath = $shortcutPath.Replace("'", "''")
$launcherContent = $launcherTemplate.Replace("__PROXY_URI__", $proxyUri).Replace("__PROXY_HOST__", $ProxyHost).Replace("__PROXY_PORT__", [string]$ProxyPort).Replace("__CODEX_HOME__", $escapedCodexHome).Replace("__SHORTCUT_PATH__", $escapedShortcutPath)

$backupPath = $null
$configChanged = $updatedConfig -cne $originalConfig

if ($configChanged -and $PSCmdlet.ShouldProcess($configPath, "Back up and remove the legacy history-hiding provider override")) {
  $backupPath = "$configPath.bak-codex-proxy-shortcut-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
  [IO.File]::WriteAllText($backupPath, $originalConfig, $utf8NoBom)
  [IO.File]::WriteAllText($configPath, $updatedConfig, $utf8NoBom)
}

if ($PSCmdlet.ShouldProcess($launcherPath, "Create or update the process-scoped Codex proxy launcher")) {
  New-Item -ItemType Directory -Path $launcherDirectory -Force | Out-Null
  [IO.File]::WriteAllText($launcherPath, $launcherContent, $utf8NoBom)
  [void][ScriptBlock]::Create([IO.File]::ReadAllText($launcherPath))
}

if ($PSCmdlet.ShouldProcess($shortcutPath, "Create or update the Codex desktop shortcut")) {
  New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
  $powerShellExe = Join-Path $PSHOME "powershell.exe"
  if (-not (Test-Path -LiteralPath $powerShellExe)) {
    $powerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  }

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $powerShellExe
  $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`""
  $shortcut.WorkingDirectory = $launcherDirectory
  $shortcut.IconLocation = "$codexExe,0"
  $shortcut.Description = "Start Codex through the process-scoped proxy $proxyUri"
  $shortcut.Save()

  $savedShortcut = $shell.CreateShortcut($shortcutPath)
  if ($savedShortcut.TargetPath -ne $powerShellExe -or $savedShortcut.Arguments -notlike "*$launcherPath*") {
    throw "Shortcut verification failed: $shortcutPath"
  }
}

$userProxyVariables = [ordered]@{}
foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")) {
  $userProxyVariables[$name] = [Environment]::GetEnvironmentVariable($name, "User")
}

[pscustomobject]@{
  Status = if ($WhatIfPreference) { "Preview only" } else { "Installed" }
  Proxy = $proxyUri
  ModelProvider = "openai (preserved)"
  HistoryCompatibility = "Existing OpenAI task history remains visible"
  LegacyProviderRestored = $legacyProviderRestored
  ConfigPath = $configPath
  ConfigChanged = $configChanged
  ConfigBackup = $backupPath
  LauncherPath = $launcherPath
  ShortcutPath = $shortcutPath
  AppUpdateBehavior = "Newest AppX selected at launch; shortcut icon self-refreshes"
  AppVersion = [string]$package.Version
  PersistentUserProxyVariables = $userProxyVariables
  SshConfigTouched = $false
}
