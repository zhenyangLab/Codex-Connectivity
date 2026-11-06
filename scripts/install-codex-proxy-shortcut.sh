#!/bin/bash
# macOS ships Bash 3.2; avoid dependencies on Homebrew or Python.
set -euo pipefail

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
Usage: bash install-codex-proxy-shortcut.sh --proxy-port PORT [options]
  --proxy-host HOST       Default: 127.0.0.1 (HTTP or mixed proxy)
  --app-path PATH         Codex.app or ChatGPT.app; auto-detect if unambiguous
  --shortcut-directory PATH  Default: ~/Desktop
  --skip-proxy-check      Generate files while proxy is offline
  --allow-non-loopback-proxy  Only for an explicitly approved remote proxy
  --dry-run              Show paths; write nothing and launch nothing
  --help
Port is required: read the HTTP/mixed port in your proxy client's settings.
HELP
}
app_executable() {
  local bundle="$1" name
  name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist") || return 1
  case "$name" in ''|*/*|.|..) return 1 ;; esac
  [ -x "$bundle/Contents/MacOS/$name" ] || return 1
  printf '%s\n' "$bundle/Contents/MacOS/$name"
}
check_proxy() {
  nc -z -G 2 "$proxy_host" "$proxy_port" >/dev/null 2>&1 ||
    fail "HTTP proxy is not listening at $proxy_host:$proxy_port. Start the proxy client first."
}

proxy_host=127.0.0.1
proxy_port=
app_path=
shortcut_directory="$HOME/Desktop"
dry_run=false
skip_proxy_check=false
allow_non_loopback=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxy-host|--proxy-port|--app-path|--shortcut-directory)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail "Missing value for $1"
      case "$1" in
        --proxy-host) proxy_host="$2" ;;
        --proxy-port) proxy_port="$2" ;;
        --app-path) app_path="$2" ;;
        --shortcut-directory) shortcut_directory="$2" ;;
      esac
      shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --skip-proxy-check) skip_proxy_check=true; shift ;;
    --allow-non-loopback-proxy) allow_non_loopback=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[ "$(uname -s)" = Darwin ] || fail 'This installer supports macOS only; use the .ps1 installer on Windows.'
case "$proxy_port" in ''|*[!0-9]*) fail 'Supply --proxy-port with the HTTP/mixed port (1-65535).' ;; esac
[ "${#proxy_port}" -le 5 ] || fail 'Port must be 1-65535.'
proxy_port=$((10#$proxy_port))
[ "$proxy_port" -ge 1 ] && [ "$proxy_port" -le 65535 ] || fail 'Port must be 1-65535.'
case "$proxy_host" in ''|*[!a-zA-Z0-9.:-]*) fail 'Invalid proxy host; supply a hostname or unbracketed IP address.' ;; esac
case "$proxy_host" in
  localhost|127.0.0.1|::1) ;;
  *) "$allow_non_loopback" || fail 'Non-loopback proxy requires explicit approval and --allow-non-loopback-proxy.' ;;
esac
case "$shortcut_directory" in /*) ;; *) fail 'Shortcut directory must be an absolute path.' ;; esac
if [ -z "$app_path" ]; then
  candidates=()
  for candidate in /Applications/Codex.app /Applications/ChatGPT.app "$HOME/Applications/Codex.app" "$HOME/Applications/ChatGPT.app"; do
    if app_executable "$candidate" >/dev/null 2>&1; then candidates+=("$candidate"); fi
  done
  [ "${#candidates[@]}" -eq 1 ] || fail 'App missing or multiple apps found. Supply --app-path with the intended Codex/ChatGPT .app.'
  app_path="${candidates[0]}"
fi
case "$app_path" in /*.app) ;; *) fail 'App path must be an absolute .app bundle path.' ;; esac
app_executable "$app_path" >/dev/null || fail 'Bundle has no valid executable.'
codex_home="${CODEX_HOME:-$HOME/.codex}"
case "$codex_home" in /*) ;; *) fail 'CODEX_HOME must be an absolute path.' ;; esac
# Never rewrite TOML with a line-oriented parser on macOS.
if [ -f "$codex_home/config.toml" ] && grep -Eq 'codex_proxy_http|codex-proxy-shortcut managed provider' "$codex_home/config.toml"; then
  fail 'Legacy provider detected. Back up and inspect config.toml to restore the built-in openai provider before installing; no files changed.'
fi
"$skip_proxy_check" || check_proxy
case "$proxy_host" in *:*) proxy_uri="http://[$proxy_host]:$proxy_port" ;; *) proxy_uri="http://$proxy_host:$proxy_port" ;; esac
shortcut_path="$shortcut_directory/Codex-HTTP-Proxy-$proxy_port.command"
printf 'Proxy: %s\nApp: %s\nCODEX_HOME: %s\nLauncher: %s\n' "$proxy_uri" "$app_path" "$codex_home" "$shortcut_path"
"$dry_run" && exit 0
mkdir -p "$shortcut_directory"
# Write beside the destination then rename, so an interrupted update leaves no partial launcher.
temporary=$(mktemp "$shortcut_directory/.codex-proxy.XXXXXX")
trap 'rm -f "$temporary"' EXIT
{
  printf '#!/bin/bash\nset -euo pipefail\n'
  declare -f fail app_executable check_proxy
  printf 'app_path=%q\nproxy_host=%q\nproxy_port=%q\nproxy=%q\nexport CODEX_HOME=%q\n' "$app_path" "$proxy_host" "$proxy_port" "$proxy_uri" "$codex_home"
  cat <<'LAUNCHER'
exe=$(app_executable "$app_path") || fail 'App moved or removed; reinstall with --app-path.'
# Refuse to reuse an existing GUI process, which would keep its old environment.
if ps -axo comm= | grep -Fx -- "$exe" >/dev/null; then
  fail 'Codex/ChatGPT is already running. Finish active tasks, quit it completely, then use this launcher.'
fi
check_proxy
for name in HTTP_PROXY HTTPS_PROXY ALL_PROXY WS_PROXY WSS_PROXY http_proxy https_proxy all_proxy ws_proxy wss_proxy; do
  export "$name=$proxy"
done
export NO_PROXY='localhost,127.0.0.1,::1,.local'
export no_proxy="$NO_PROXY"
exec "$exe" "--proxy-server=$proxy" '--proxy-bypass-list=localhost;127.0.0.1;::1' --disable-quic
LAUNCHER
} > "$temporary"
/bin/bash -n "$temporary"
chmod 700 "$temporary"
mv -f "$temporary" "$shortcut_path"
printf 'Installed. After finishing active tasks, quit the app fully and double-click the .command launcher.\n'
