---
name: codex-proxy-shortcut
description: Diagnose and fix Windows Codex or ChatGPT Desktop showing Connecting/Reconnecting 1/5 through 5/5 when a local HTTP proxy is required. Configure a ChatGPT-authenticated HTTP/SSE-only Codex provider, generate a launcher that injects proxy variables only into the launched Codex process tree, and create or repair a desktop shortcut. Use for Windows Codex proxy shortcuts, five fixed reconnect attempts, Responses WebSocket proxy failures, or rebuilding the launcher after an AppX update. Do not use this workflow to change Windows system proxy, persistent user environment variables, WinHTTP, routing, Remote Control, or SSH configuration.
---

# Codex Proxy Shortcut

Fix the five-attempt startup delay at its transport source, then deliver the fix through a Windows desktop shortcut. Keep all proxy environment variables process-scoped.

## Non-negotiable boundaries

- Work on Windows only.
- Never modify Windows system proxy, WinINET, WinHTTP, registry proxy keys, routing, firewall rules, or persistent User/Machine environment variables.
- Never use `setx` or `[Environment]::SetEnvironmentVariable(...)`.
- Never modify, remove, or rewrite `%USERPROFILE%\.ssh\config`.
- Never disable Remote Control or remove its enrollment unless the user separately and explicitly requests that change.
- Back up `config.toml` immediately before changing it.
- Do not launch or restart Codex automatically while an active task is running.
- Explain that `model_provider = "codex_proxy_http"` is a Codex-wide transport choice, while the proxy variables themselves exist only in the shortcut-launched process tree.

## Workflow

### 1. Identify the five-retry signature

Read [references/five-connecting.md](references/five-connecting.md) before changing anything.

If `sqlite3` is available, inspect `%USERPROFILE%\.codex\logs_2.sqlite` for recent `codex_core::responses_retry` records. Treat this exact target plus `stream disconnected - retrying sampling request (N/5)` as the Responses WebSocket fallback problem.

Do not infer this cause from every use of the word "reconnecting." Distinguish:

- `codex_core::responses_retry`: visible turn-level `1/5` through `5/5`; apply the HTTP/SSE-only provider fix.
- `codex_app_server_transport::transport::remote_control::websocket`: Remote Control connection; report separately and leave unchanged.
- SSH errors: remote environment connectivity; leave `%USERPROFILE%\.ssh\config` unchanged.

### 2. Check the current state

Inspect without changing:

- The requested proxy host and port.
- Whether the proxy port is listening.
- The newest `OpenAI.Codex` AppX package and `app\ChatGPT.exe`.
- `%USERPROFILE%\.codex\config.toml`.
- The requested desktop shortcut and launcher, if present.
- User and Machine `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` values. Report unexpected persistent values; do not remove them without an explicit request.

If the HTTP-only provider and shortcut already match the requested values, report that the setup is already complete and do not rewrite files.

### 3. Install or repair

Run the bundled script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\install-codex-proxy-shortcut.ps1" -ProxyHost "127.0.0.1" -ProxyPort 12450
```

Useful options:

```powershell
# Preview without writing.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\install-codex-proxy-shortcut.ps1" -ProxyHost "127.0.0.1" -ProxyPort 12450 -WhatIf

# Choose a shortcut name and launcher root.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\install-codex-proxy-shortcut.ps1" -ProxyHost "127.0.0.1" -ProxyPort 12450 -ShortcutName "Codex HTTP 12450" -LauncherRoot "D:\Codex\codex-proxy-shortcuts"
```

Use `-AllowNonLoopbackProxy` only after the user explicitly requests a non-loopback proxy and understands the exposure.

The script performs two complementary changes:

1. Selects a custom ChatGPT-authenticated provider with `supports_websockets = false`, so Codex uses HTTP/SSE immediately instead of failing five WebSocket attempts first.
2. Creates a launcher that sets HTTP, HTTPS, WebSocket, and all-proxy variables only in its own process, then starts the current Store-installed `ChatGPT.exe` with Chromium proxy flags.

### 4. Verify without restarting the active app

Verify:

- `config.toml` contains exactly one active `model_provider = "codex_proxy_http"`.
- The managed provider has the ChatGPT Codex base URL, `requires_openai_auth = true`, and `supports_websockets = false`.
- The launcher parses as PowerShell.
- The shortcut targets Windows PowerShell and references the generated launcher.
- The shortcut icon resolves to the current Store-installed `ChatGPT.exe`.
- User and Machine proxy variables were not created or changed.
- `%USERPROFILE%\.ssh\config` was not touched.

Ask the user to completely quit Codex/ChatGPT and reopen it with the new shortcut. Do not perform that restart from the task that created the shortcut.

### 5. Verify after the user restarts

For a fresh test turn, query only records newer than the restart time. Success means there are no new `codex_core::responses_retry` messages showing the fixed `1/5` through `5/5` sequence.

If HTTP/SSE still times out, test the local HTTP proxy itself and inspect the exact `sampling_error`. Do not re-enable WebSockets as a generic fallback.

## Reusable examples

- "给 Windows Codex 做一个只让自身走 `127.0.0.1:12450` 的快捷方式，并解决五次 Connecting。"
- "Codex 每次先 Reconnecting 1/5 到 5/5 才能回复，帮我强制用 HTTP/SSE。"
- "Codex 更新后代理快捷方式失效了，按现在的 AppX 路径重建。"
- "检查 Codex 是否真的从第一次请求就走本地 HTTP 代理，不要修改系统代理。"
