# Five Connecting diagnosis

## Core signature

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

When HTTPS through a local proxy works but the Responses WebSocket path does not, Codex can spend all five retries on WebSocket before falling back to HTTP/SSE. The reliable workaround is an OpenAI-authenticated custom provider with WebSockets disabled:

```toml
model_provider = "codex_proxy_http"

[model_providers.codex_proxy_http]
name = "ChatGPT HTTP/SSE"
base_url = "https://chatgpt.com/backend-api/codex"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
```

This changes Codex transport only. It does not configure an operating-system proxy. The generated launcher supplies the local proxy to the launched Codex process tree.

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

### Remote Control WebSocket

Target:

```text
codex_app_server_transport::transport::remote_control::websocket
```

This is the optional cross-device Remote Control connection. It is not the Responses transport used for a normal model turn. Do not disable it as part of this skill.

### SSH reconnection

Messages involving `ssh`, remote hosts, or an SSH-launched app server belong to remote project connectivity. They are outside this skill. Preserve `%USERPROFILE%\.ssh\config`.

### HTTP/SSE timeout

If `supports_websockets = false` is already active and `codex_core::responses_retry` continues, inspect the exact error and test:

```powershell
Test-NetConnection 127.0.0.1 -Port 12450 -InformationLevel Quiet
curl.exe --proxy http://127.0.0.1:12450 -I https://chatgpt.com/
```

An HTTP status response proves the proxy path is reachable; authentication success is not required for this connectivity test.

## Supporting sources

- Codex configuration documents `model_provider`, `requires_openai_auth`, and `supports_websockets`: <https://developers.openai.com/codex/config-reference/>
- OpenAI Codex issue describing five WebSocket retries before HTTP fallback: <https://github.com/openai/codex/issues/19821>
- OpenAI Codex issue demonstrating the HTTP-only provider workaround: <https://github.com/openai/codex/issues/22634>
