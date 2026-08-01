# Codex connectivity diagnosis

## Model response signature

The user-visible sequence:

```text
Reconnecting... 1/5
Reconnecting... 2/5
Reconnecting... 3/5
Reconnecting... 4/5
Reconnecting... 5/5
```

usually maps to log target `codex_core::responses_retry` and messages such as:

```text
stream disconnected - retrying sampling request (N/5 ...)
sampling_error=request timed out
sampling_error=stream disconnected before completion
```

When HTTPS through a local proxy works but the Responses WebSocket path bypasses that proxy, Codex can spend all five retries on WebSocket before falling back to HTTP/SSE.

Keep the built-in `openai` provider and route the WebSocket itself through the process-scoped proxy. The launcher must set uppercase and lowercase HTTP, HTTPS, WS, WSS, ALL, and NO proxy variables before starting Codex. It also passes Chromium proxy flags and disables QUIC.

Do not use a custom provider as the default workaround. Codex defaults `thread/list` to the active provider ID, so selecting a different provider can hide intact tasks created under `openai`.

## Missing history after the legacy shortcut

Legacy versions of this Skill wrote:

```toml
model_provider = "codex_proxy_http"

# BEGIN codex-proxy-shortcut managed provider
[model_providers.codex_proxy_http]
name = "ChatGPT HTTP/SSE"
base_url = "https://chatgpt.com/backend-api/codex"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
# END codex-proxy-shortcut managed provider
```

This did not delete history. It changed the active provider ID, while older task metadata still used `openai`. Because an omitted `thread/list.modelProviders` filter defaults to the active provider, the sidebar excluded those older tasks.

The current installer repairs this automatically:

1. Back up `config.toml`.
2. Remove only the managed legacy provider block.
3. Replace only a top-level `model_provider = "codex_proxy_http"` selection with `model_provider = "openai"`.
4. Leave session JSONL files and `state_5.sqlite` untouched.
5. Pin process-local `CODEX_HOME` in the generated launcher so both shortcuts read the same history location.

New installations never create the custom provider, so users do not need a separate history-repair step.

## Store update behavior

The Microsoft Store installs each Codex version under a versioned WindowsApps directory. A shortcut that directly targets one `ChatGPT.exe` path or an old launcher can become stale after an update.

The managed shortcut avoids that dependency:

1. The shortcut targets stable Windows PowerShell plus the generated launcher, not `ChatGPT.exe`.
2. The launcher runs `Get-AppxPackage -Name OpenAI.Codex`, sorts by version, and selects the newest package on every start.
3. The launcher reapplies uppercase and lowercase HTTP, HTTPS, WS, WSS, ALL, and NO proxy variables on every start.
4. The launcher pins the same `CODEX_HOME` so an app update cannot switch local history roots.
5. After resolving the newest package, the launcher updates only the shortcut icon if it still references an older WindowsApps version. Icon-refresh failure is non-fatal.

Therefore an ordinary Store update does not require a new shortcut. If five retries return after an update, inspect the launcher first: legacy launchers commonly contain only HTTP/HTTPS/ALL proxy variables and omit WS/WSS or `--disable-quic`.

## Remote Control signature

The UI may show:

```text
Unable to update remote control status
```

Relevant log targets include:

```text
codex_app_server_transport::transport::remote_control::websocket
```

Common failures include Windows socket error `10060` while connecting to:

```text
wss://chatgpt.com/backend-api/wham/remote/control/server
```

Do not disable Remote Control or delete its enrollment. The launcher must set both uppercase and lowercase `WS_PROXY` and `WSS_PROXY` before starting ChatGPT/Codex. This keeps the Remote Control transport on WebSocket while routing it through the same local HTTP proxy.

After restarting through the shortcut, ask the user to enable Allow connections again and confirm that the UI accepts the change. Do not automate authentication or the toggle.

## Read-only log query

Use this query only when `sqlite3` exists:

```powershell
$db = Join-Path $env:USERPROFILE ".codex\logs_2.sqlite"
sqlite3 -readonly -header -column $db @"
select
  datetime(ts,'unixepoch','localtime') as time,
  level,
  target,
  substr(feedback_log_body, max(1,length(feedback_log_body)-1000), 1000) as tail
from logs
where ts > (select max(ts)-86400 from logs)
  and level in ('WARN','ERROR')
  and target = 'codex_core::responses_retry'
order by ts desc, ts_nanos desc
limit 50;
"@
```

Avoid printing broad log bodies: they can contain task text and paths.

## Similar but separate problems

### Process-scoped proxy boundary

The launcher environment is inherited only by ChatGPT/Codex and its child processes. It does not create persistent User/Machine environment variables and does not modify Windows system proxy settings.

This distinction matters for traffic usage: browsers, messaging clients, download tools, and unrelated applications retain their existing network configuration instead of consuming local proxy traffic.

Remote Control is still a separate WebSocket path from normal model turns. Route it through the process proxy; do not treat disabling it as the connectivity fix.

### Provider-scoped task listing

The active provider is also a history-list filter, not only a transport setting. Preserve the built-in `openai` provider for normal ChatGPT-authenticated Codex use. Never rewrite thread metadata or SQLite databases to compensate for a provider change.

### SSH reconnection

Messages involving `ssh`, remote hosts, or an SSH-launched app server belong to remote project connectivity. They are outside this skill. Preserve `%USERPROFILE%\.ssh\config`.

### WebSocket proxy timeout

If `codex_core::responses_retry` continues after launching through the shortcut, inspect the exact error and test:

```powershell
Test-NetConnection 127.0.0.1 -Port 12450 -InformationLevel Quiet
curl.exe --proxy http://127.0.0.1:12450 -I https://chatgpt.com/
```

An HTTP status response proves the proxy path is reachable; authentication success is not required for this connectivity test.

The HTTP test alone does not prove WebSocket tunneling works. Confirm that the proxy supports WebSocket CONNECT traffic to `wss://chatgpt.com` before changing Codex transport settings.

## Supporting sources

- Codex configuration documents the built-in `openai` provider and reserved provider IDs: <https://developers.openai.com/codex/config-reference/>
- Codex app-server source defaults an omitted thread-list provider filter to the active provider: <https://github.com/openai/codex/blob/main/codex-rs/app-server/src/request_processors/thread_processor.rs>
- OpenAI Codex issue describing five WebSocket retries before HTTP fallback: <https://github.com/openai/codex/issues/19821>
- OpenAI Codex issue requesting a provider-preserving HTTPS-only switch: <https://github.com/openai/codex/issues/28503>
