---
name: codex-connectivity
description: Diagnose and stabilize Windows Codex or ChatGPT Desktop connectivity when a local HTTP proxy is required. Create a process-scoped proxy launcher and desktop shortcut, eliminate fixed Connecting/Reconnecting 1/5 through 5/5 delays by selecting HTTP/SSE for model responses, and route Remote Control WebSockets through the same proxy to address "Unable to update remote control status" and unstable mobile-to-desktop connections. Use for Windows Codex proxy isolation, reduced proxy traffic, Responses WebSocket failures, Remote Control connection failures, mobile connection instability, or shortcut repair after an AppX update. Never turn on a system-wide proxy or modify persistent User/Machine proxy variables, WinHTTP, routing, firewall, or SSH configuration.
---

# Codex Connectivity

Stabilize the two Codex network paths that commonly fail behind a local proxy:

1. Use HTTP/SSE for model responses to skip five failed Responses WebSocket attempts.
2. Keep Remote Control on WebSocket, but make it inherit the shortcut's `WS_PROXY` and `WSS_PROXY`.

Keep the proxy limited to the shortcut-launched Codex process tree so unrelated Windows applications continue using their original network path.

## Non-negotiable boundaries

- Work on Windows only.
- Never modify Windows system proxy, WinINET, WinHTTP, registry proxy keys, routes, firewall rules, or persistent User/Machine environment variables.
- Never use `setx` or `[Environment]::SetEnvironmentVariable(...)`.
- Never modify, remove, or rewrite `%USERPROFILE%\.ssh\config`.
- Never disable Remote Control, delete enrollment data, or edit its SQLite state as part of this workflow.
- Back up `config.toml` immediately before changing it.
- Do not launch, close, or restart Codex while an active task is running.
- Explain that the HTTP-only model provider is a Codex-wide transport choice, while proxy variables are limited to the process tree started by the dedicated shortcut.
- Explain that process-scoped proxying avoids routing browsers, messaging apps, download tools, and other unrelated software through the proxy, reducing unnecessary proxy traffic.

## Workflow

### 1. Classify the connection failure

Read [references/connectivity-diagnosis.md](references/connectivity-diagnosis.md) before changing anything.

If `sqlite3` is available, inspect recent records in `%USERPROFILE%\.codex\logs_2.sqlite`. Avoid broad log output because task text and paths can appear in log bodies.

Distinguish:

- `codex_core::responses_retry` plus `stream disconnected - retrying sampling request (N/5)`: model Responses WebSocket fallback; configure the HTTP/SSE-only provider.
- `codex_app_server_transport::transport::remote_control::websocket`, Windows error `10060`, or the UI message "Unable to update remote control status": Remote Control WebSocket; keep the feature enabled and make the Codex process inherit `WS_PROXY/WSS_PROXY`.
- SSH or remote-project errors: outside this skill; preserve `%USERPROFILE%\.ssh\config`.

Both first and second categories can occur at the same time. Fix both with the dedicated launcher, but do not conflate their transports.

### 2. Check the current state

Inspect without changing:

- The requested proxy host and port.
- Whether the proxy port is listening.
- The newest `OpenAI.Codex` AppX package and `app\ChatGPT.exe`.
- `%USERPROFILE%\.codex\config.toml`.
- The requested desktop shortcut and launcher.
- User and Machine `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` values.

Report unexpected persistent proxy variables; do not remove them without an explicit request.

If the HTTP-only provider and shortcut already match the requested values, report that the setup is complete and do not rewrite files.

### 3. Install or repair

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\install-codex-proxy-shortcut.ps1" -ProxyHost "127.0.0.1" -ProxyPort 12450
```

Preview first when requested:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\install-codex-proxy-shortcut.ps1" -ProxyHost "127.0.0.1" -ProxyPort 12450 -WhatIf
```

Use `-AllowNonLoopbackProxy` only after explicit user approval for a non-loopback proxy.

The script:

1. Selects a ChatGPT-authenticated provider with `supports_websockets = false`, making model turns use HTTP/SSE immediately.
2. Generates a launcher that sets uppercase and lowercase HTTP, HTTPS, WS, WSS, ALL, and NO proxy variables only in the launcher process.
3. Starts the newest Store-installed `ChatGPT.exe` with Chromium proxy flags and QUIC disabled.
4. Creates or repairs a desktop shortcut without binding it to a specific AppX version.

### 4. Verify without restarting the active app

Verify:

- `config.toml` has one active `model_provider = "codex_proxy_http"`.
- The managed provider uses the ChatGPT Codex base URL, OpenAI authentication, and `supports_websockets = false`.
- The launcher parses as PowerShell and contains HTTP, HTTPS, WS, and WSS proxy variables.
- The shortcut targets Windows PowerShell and references the generated launcher.
- The shortcut icon resolves to the newest Store-installed `ChatGPT.exe`.
- User and Machine proxy variables were not created or changed.
- `%USERPROFILE%\.ssh\config` was not touched.

Ask the user to completely quit Codex/ChatGPT and reopen it with the dedicated shortcut. Do not restart the app from the task that created the shortcut.

### 5. Verify after restart

For model responses:

- Start a fresh test turn.
- Query only log records newer than the restart.
- Confirm no new fixed `codex_core::responses_retry` sequence reaches `1/5` through `5/5`.

For mobile Remote Control:

- Ask the user to open Settings > Connections > Control this computer and enable Allow connections.
- Confirm the UI no longer shows "Unable to update remote control status."
- Inspect new Remote Control log records for successful connection or the absence of repeated `os error 10060`.
- Do not automate the authentication or connection toggle.

If Remote Control still fails while HTTP/SSE works, test whether the local HTTP proxy supports WebSocket tunneling to `wss://chatgpt.com`. Do not re-enable Responses WebSocket as a generic workaround.

## Reusable examples

- "Only route Windows Codex through 127.0.0.1:12450; do not proxy my whole computer."
- "Fix Codex Reconnecting 1/5 through 5/5 and reduce unnecessary proxy traffic."
- "Fix Unable to update remote control status so my phone can connect to this computer."
- "Rebuild the Codex connectivity shortcut after the Store app updates."
