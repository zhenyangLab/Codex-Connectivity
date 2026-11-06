---
name: codex-connectivity
description: Diagnose Codex or ChatGPT Desktop proxy connectivity on Windows and macOS. Ask for the target operating system and local HTTP or mixed proxy port, explain where to find that port, then create a process-scoped launcher that preserves CODEX_HOME and task history. Use for repeated reconnects, Remote Control connection failures, or proxy launcher repair. SSH/server login is outside this skill.
---

# Codex Connectivity

Route the desktop app and its child processes through a local HTTP proxy. Preserve the existing `CODEX_HOME`, account data and built-in `openai` provider. A reachable HTTP proxy does not prove model WebSocket or Remote Control success; verify both after the user restarts.

## 1. Ask before configuring

At first use, actively present these questions in the user's language, with selectable choices when the host provides a question tool. Otherwise use a numbered text menu and wait for a reply. Do not silently infer answers from the host OS or use a sample port. For a subsequent repair, reuse answers already explicitly given in this conversation; ask only for missing or changed values.

1. **这次要配置的电脑是什么系统？**
   - Windows 10 / 11
   - macOS（Mac）
   - 不确定 / 其他系统
2. **本地代理的 HTTP 或 Mixed（混合）端口是多少？**
   - 我知道，输入端口（1–65535）
   - 不知道，帮我查看
   - 还没有代理软件 / 本地代理

Allow free-text answers; never turn choosing “我知道” into accepting a default numeric port. If the user already explicitly supplied OS and port, acknowledge them and proceed without asking again. Host detection can be shown as a hint, not a replacement for confirming the target computer. Linux is unsupported; explain that instead of running a Windows or Mac installer.

For “不知道”, read [proxy-port.md](references/proxy-port.md) and explain where to look. Offer:

- 查看代理软件设置（HTTP / Mixed Port，推荐）
- 只读检查当前电脑的代理设置和监听端口
- 告诉我代理软件名称，按软件引导

If read-only inspection is chosen, list likely endpoints and process names, then have the user choose/confirm the endpoint. A listening socket, system proxy value, or common port number is only a candidate. Do not auto-select it. Never dump whole proxy configuration files, subscriptions, credentials, or broad logs.

If no local proxy exists, stop configuration and explain that this skill does not supply a proxy service. A pure SOCKS port, external controller/API port or subscription server port is not an HTTP proxy port. Ask for an HTTP/mixed listener instead. Use `127.0.0.1` for a proxy on the same computer; ask for the host if the proxy is elsewhere, and obtain explicit approval before enabling the non-loopback option.

## 2. Inspect and route by OS

After the answers arrive, check the selected endpoint and installation without changing files. A TCP check proves only that something listens. If needed, use a bounded explicit HTTP proxy request such as `curl --connect-timeout 5 --max-time 15 --proxy http://HOST:PORT -I https://chatgpt.com/`; a status response alone does not prove authentication or WebSocket tunneling works.

- **Windows:** Read [windows.md](references/windows.md). Run `scripts/install-codex-proxy-shortcut.ps1` with the confirmed `-ProxyHost` and required `-ProxyPort`. It resolves the latest Store AppX on each launch, preserves history, repairs the old managed provider with a backup, and refreshes the shortcut icon. Preview with `-WhatIf` when requested.
- **macOS:** Read [macos.md](references/macos.md). Run `scripts/install-codex-proxy-shortcut.sh` with the confirmed `--proxy-port`; use `--app-path` when multiple bundles exist or the location is nonstandard. It creates an executable Desktop `.command` launcher and rereads `CFBundleExecutable` at every start. Preview with `--dry-run` when requested. It never changes TOML; if a legacy provider is detected, inspect and back up the configuration before a narrowly scoped repair rather than running the Windows script.

For error classification, consult [connectivity-diagnosis.md](references/connectivity-diagnosis.md). Its AppX, PowerShell and socket error 10060 details apply to Windows. On macOS inspect only relevant, recent logs in the actual `CODEX_HOME` or app log directory; do not assume Windows error codes or fixed log schema.

## Boundaries

- Keep proxy variables local to the dedicated launcher and the app process tree. Do not change system proxy settings, routes, firewall rules, SSH configuration, persistent environment variables, shell startup files, or `launchctl setenv`.
- Do not change provider IDs as a transport workaround, create a new `CODEX_HOME`, edit history databases, delete pairing data, disable Remote Control, or modify signed app bundle contents.
- Back up `config.toml` immediately before any authorized legacy repair. Preserve unrelated settings and custom providers; do not force a user-selected custom provider to `openai`.
- Installation creates files only; do not launch, close or restart the active app during this task. The launchers refuse to reuse an existing app process because its environment would remain unchanged.
- Explain that unrelated applications retain their existing network settings; existing system/TUN proxy settings may still route those applications independently of this launcher.

## 3. Verify and hand off

Check launcher syntax, selected proxy values, the preserved `CODEX_HOME`, and the shortcut target. Confirm files outside the generated launcher/shortcut and any explicitly repaired legacy config remain unchanged. If the desired setup already exists, report it rather than rewriting it.

Ask the user to finish active tasks, quit the app completely and reopen through the dedicated shortcut. macOS: use Quit / ⌘Q, not just the window close button. Then verify a fresh model turn, existing history visibility, and (if needed) the Remote Control UI and fresh transport logs. Do not automate authentication or connection toggles. Do not claim end-to-end success until this has been observed.

If connection failures persist, inspect actual errors and proxy WebSocket support. Do not broaden proxy scope or change provider IDs as a fallback.
