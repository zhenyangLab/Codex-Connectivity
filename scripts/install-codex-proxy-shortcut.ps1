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
$markerStart = "# BEGIN codex-proxy-shortcut managed provider"
$markerEnd = "# END codex-proxy-shortcut managed provider"
$managedPattern = "(?ms)^# BEGIN codex-proxy-shortcut managed provider\r?\n.*?^# END codex-proxy-shortcut managed provider\r?\n?"
$configWithoutManagedBlock = [regex]::Replace($originalConfig, $managedPattern, "")

if ($configWithoutManagedBlock -match "(?m)^\s*\[model_providers\.codex_proxy_http\]\s*$") {
  throw "A model_providers.codex_proxy_http table already exists outside this skill's managed block. Rename it or choose a manual merge."
}

$providerSelectionPattern = "(?m)^(?<indent>\s*)model_provider\s*=\s*.*$"
$firstTable = [regex]::Match($configWithoutManagedBlock, "(?m)^\s*\[")
if ($firstTable.Success) {
  $topLevelPrefix = $configWithoutManagedBlock.Substring(0, $firstTable.Index)
  $tableContent = $configWithoutManagedBlock.Substring($firstTable.Index)
} else {
  $topLevelPrefix = $configWithoutManagedBlock
  $tableContent = ""
}

$providerMatches = [regex]::Matches($topLevelPrefix, $providerSelectionPattern)
if ($providerMatches.Count -gt 1) {
  throw "Multiple top-level model_provider entries were found in config.toml. Resolve them before using this installer."
}

if ($providerMatches.Count -eq 1) {
  $updatedTopLevelPrefix = [regex]::Replace(
    $topLevelPrefix,
    $providerSelectionPattern,
    '${indent}model_provider = "codex_proxy_http"',
    1
  )
} else {
  $selection = "model_provider = `"codex_proxy_http`"`r`n"
  $updatedTopLevelPrefix = $selection + "`r`n" + $topLevelPrefix
}
$updatedConfig = $updatedTopLevelPrefix + $tableContent

$managedBlock = @"
$markerStart
[model_providers.codex_proxy_http]
name = "ChatGPT HTTP/SSE"
base_url = "https://chatgpt.com/backend-api/codex"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
$markerEnd
"@
$updatedConfig = $updatedConfig.TrimEnd() + "`r`n`r`n" + $managedBlock.Trim() + "`r`n"

$launcherTemplate = @'
param()

$ErrorActionPreference = "Stop"

# These variables exist only in this launcher and the Codex processes it starts.
# This script does not change User/Machine environment variables or Windows proxy settings.
$proxy = "__PROXY_URI__"
$proxyHost = "__PROXY_HOST__"
$proxyPort = __PROXY_PORT__
$noProxy = "localhost,127.0.0.1,::1,.local"

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

$launcherContent = $launcherTemplate.Replace("__PROXY_URI__", $proxyUri).Replace("__PROXY_HOST__", $ProxyHost).Replace("__PROXY_PORT__", [string]$ProxyPort)

$backupPath = $null
$configChanged = $updatedConfig -cne $originalConfig

if ($configChanged -and $PSCmdlet.ShouldProcess($configPath, "Back up and configure the HTTP/SSE-only Codex provider")) {
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
  $shortcut.Description = "Start Codex through $proxyUri using HTTP/SSE transport"
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
  HttpOnlyProvider = "codex_proxy_http"
  ConfigPath = $configPath
  ConfigChanged = $configChanged
  ConfigBackup = $backupPath
  LauncherPath = $launcherPath
  ShortcutPath = $shortcutPath
  AppVersion = [string]$package.Version
  PersistentUserProxyVariables = $userProxyVariables
  SshConfigTouched = $false
}
