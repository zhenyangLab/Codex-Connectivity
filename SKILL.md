---
name: codex-connectivity
description: Diagnose and stabilize Windows Codex or ChatGPT Desktop connectivity when a local HTTP proxy is required. Create an AppX-update-safe, process-scoped proxy launcher and desktop shortcut that preserve the built-in OpenAI provider and existing task history, route model and Remote Control WebSockets through the local proxy, address Connecting/Reconnecting 1/5 through 5/5 and "Unable to update remote control status," self-refresh the versioned shortcut icon, and repair legacy codex_proxy_http setups that hide older history. Use for Windows Codex proxy isolation, reduced proxy traffic, missing history after a proxy shortcut, Responses WebSocket failures, Remote Control connection failures, mobile connection instability, a stale launcher after a Store update, or shortcut repair after an AppX update. Never turn on a system-wide proxy or modify persistent User/Machine proxy variables, WinHTTP, routing, firewall, SSH configuration, or thread databases.
---

# Codex Connectivity

Stabilize the two Codex WebSocket paths that commonly fail behind a local proxy:

1. Route Responses WebSocket through the shortcut's HTTP/HTTPS/WS/WSS proxy variables.
2. Route Remote Control WebSocket through the same process-scoped proxy.

Keep the built-in `openai` provider unchanged so existing tasks remain visible. Keep the proxy limited to the shortcut-launched Codex process tree so unrelated Windows applications continue using their original network path.

## Non-negotiable boundaries

- Work on Windows only.
- Never modify Windows system proxy, WinINET, WinHTTP, registry proxy keys, routes, firewall rules, or persistent User/Machine environment variables.
- Never use `setx` or `[Environment]::SetEnvironmentVariable(...)`.
- Never modify, remove, or rewrite `%USERPROFILE%\.ssh\config`.
- Never disable Remote Control, delete enrollment data, or edit Codex thread or Remote Control SQLite state as part of this workflow.
- Never select a custom model provider during normal installation. Codex filters the default task list by the active provider, so changing provider IDs can make intact history look missing.
- Back up `config.toml` immediately before changing it.
- Do not launch, close, or restart Codex while an active task is running.
- Explain that the launcher preserves `CODEX_HOME` and the built-in `openai` provider while proxy variables remain limited to the process tree started by the dedicated shortcut.
- Explain that process-scoped proxying avoids routing browsers, messaging apps, download tools, and other unrelated software through the proxy, reducing unnecessary proxy traffic.

## Workflow

### 1. Classify the connection failure

Read [references/connectivity-diagnosis.md](references/connectivity-diagnosis.md) before changing anything.

If `sqlite3` is available, inspect recent records in `%USERPROFILE%\.codex\logs_2.sqlite`. Avoid broad log output because task text and paths can appear in log bodies.

Distinguish:

- `codex_core::responses_retry` plus `stream disconnected - retrying sampling request (N/5)`: model Responses WebSocket is not reaching the proxy; repair the process-scoped HTTP/HTTPS/WS/WSS proxy launcher.
- `codex_app_server_transport::transport::remote_control::websocket`, Windows error `10060`, or the UI message "Unable to update remote control status": Remote Control WebSocket; keep the feature enabled and make the Codex process inherit `WS_PROXY/WSS_PROXY`.
- Existing tasks disappear only after the proxy shortcut is installed: inspect top-level `model_provider` and the legacy managed block before touching history files. A selected `codex_proxy_http` provider filters out older `openai` threads; the data is not deleted.
- SSH or remote-project errors: outside this skill; preserve `%USERPROFILE%\.ssh\config`.

Both first and second categories can occur at the same time. Fix both with the dedicated launcher, but do not conflate their transports.

### 2. Check the current state

Inspect without changing:

- The requested proxy host and port.
- Whether the proxy port is listening.
- The newest `OpenAI.Codex` AppX package and `app\ChatGPT.exe`.
- `%USERPROFILE%\.codex\config.toml`.
- The requested desktop shortcut and launcher.
- Whether the launcher dynamically selects the newest AppX package and contains HTTP, HTTPS, WS, WSS, `CODEX_HOME`, and `--disable-quic` settings.
- Whether the shortcut icon still points to an older versioned WindowsApps directory.
- User and Machine `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` values.
- Whether the legacy `codex_proxy_http` managed block or selection exists.

Report unexpected persistent proxy variables; do not remove them without an explicit request.

If the built-in `openai` provider is preserved, the shortcut matches the requested values, and no legacy managed block exists, report that the setup is complete and do not rewrite files.

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

1. Leaves the built-in `openai` provider unchanged for new installations.
2. Automatically removes this Skill's legacy `codex_proxy_http` managed block and restores `model_provider = "openai"` when upgrading an affected installation. It backs up `config.toml` first and never edits thread files or databases.
3. Pins the launcher to the inspected `CODEX_HOME`, so the normal shortcut and proxy shortcut use the same local task history.
4. Generates a launcher that sets uppercase and lowercase HTTP, HTTPS, WS, WSS, ALL, and NO proxy variables only in the launcher process.
5. Starts the newest Store-installed `ChatGPT.exe` with Chromium proxy flags and QUIC disabled.
6. Creates or repairs a desktop shortcut without binding it to a specific AppX version.
7. Embeds the shortcut path in the launcher and refreshes its versioned icon after future Store updates without changing the shortcut target or proxy scope.

### 4. Handle future AppX updates

For an ordinary Codex Store update, keep using the same shortcut. The launcher resolves the newest `OpenAI.Codex` package on every start, reapplies all process-scoped proxy variables, preserves `CODEX_HOME`, and refreshes the icon when the versioned WindowsApps path changes.

Re-run the installer only when the launcher is missing required proxy variables, the shortcut no longer targets the launcher, or a Codex networking change causes new retry logs. Do not recreate a custom provider as an update workaround.

### 5. Verify without restarting the active app

Verify:

- `config.toml` does not select `codex_proxy_http` and contains no legacy managed provider block.
- The active provider remains the built-in `openai` provider, explicitly or by default.
- The launcher parses as PowerShell and contains HTTP, HTTPS, WS, and WSS proxy variables.
- The launcher sets process-local `CODEX_HOME` to the same directory inspected during installation.
- The launcher embeds the shortcut path, selects the newest AppX package, and contains best-effort icon self-refresh logic.
- The shortcut targets Windows PowerShell and references the generated launcher.
- The shortcut icon resolves to the newest Store-installed `ChatGPT.exe`.
- User and Machine proxy variables were not created or changed.
- `%USERPROFILE%\.ssh\config` was not touched.

Ask the user to completely quit Codex/ChatGPT and reopen it with the dedicated shortcut. Do not restart the app from the task that created the shortcut.

### 6. Verify after restart

For model responses:

- Start a fresh test turn.
- Query only log records newer than the restart.
- Confirm no new fixed `codex_core::responses_retry` sequence reaches `1/5` through `5/5`.
- Confirm existing OpenAI-provider task history remains visible in the sidebar.

For mobile Remote Control:

- Ask the user to open Settings > Connections > Control this computer and enable Allow connections.
- Confirm the UI no longer shows "Unable to update remote control status."
- Inspect new Remote Control log records for successful connection or the absence of repeated `os error 10060`.
- Do not automate the authentication or connection toggle.

If either WebSocket path still fails, test whether the local HTTP proxy supports WebSocket tunneling to `wss://chatgpt.com`. Do not silently switch to a custom provider: that changes the provider-scoped task list and recreates the missing-history problem.

## Reusable examples

- "Only route Windows Codex through 127.0.0.1:12450; do not proxy my whole computer."
- "Fix Codex Reconnecting 1/5 through 5/5 and reduce unnecessary proxy traffic."
- "Fix Unable to update remote control status so my phone can connect to this computer."
- "Rebuild the Codex connectivity shortcut after the Store app updates."
- "Make my Codex proxy shortcut survive future Store updates without recreating it."
- "My task history disappeared after installing the old proxy shortcut; restore it without editing the thread database."
