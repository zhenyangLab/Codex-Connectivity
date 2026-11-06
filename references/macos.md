# macOS launcher

Use the confirmed HTTP/mixed endpoint. The example port below is illustrative.

```bash
bash "<skill-dir>/scripts/install-codex-proxy-shortcut.sh" \
  --proxy-host 127.0.0.1 --proxy-port 7897 --dry-run
bash "<skill-dir>/scripts/install-codex-proxy-shortcut.sh" \
  --proxy-host 127.0.0.1 --proxy-port 7897
```

The installer checks `/Applications` and `~/Applications` for `Codex.app` and `ChatGPT.app`. If both exist, ask which app is intended and pass an absolute `--app-path`. It reads the bundle's `CFBundleExecutable`; it does not assume the internal binary is named Codex. Standard Apple Silicon and Intel macOS use the same script; the app itself must support the host hardware.

Output: `~/Desktop/Codex-HTTP-Proxy-<port>.command`. Use `--shortcut-directory` for a custom absolute Desktop path. `--skip-proxy-check` allows offline file generation but the generated launcher always checks the listener before starting. `--allow-non-loopback-proxy` requires explicit user approval.

The installer uses macOS Bash 3.2, PlistBuddy and nc; no Homebrew, Python or administrator access is needed. The launcher quotes embedded values, pins the inspected `CODEX_HOME` (default `~/.codex`), and directly executes the current bundle executable with process-local uppercase/lowercase HTTP, HTTPS, WS, WSS, ALL and NO proxy variables plus Chromium proxy flags. It does not use `open -a`, which may reuse a running process, or `launchctl setenv`, which changes the login session environment.

A normal app update at the same bundle path is supported by rereading bundle metadata on every launch. If the app is moved/renamed, rerun with the new `--app-path`. This is a terminal `.command` shortcut, not a repackaged or resigned application. Terminal may remain visible while the app runs.

The installer never edits `config.toml`. Legacy `codex_proxy_http` markers stop installation with no writes; inspect and back up config before a separate focused repair. Preserve a deliberately selected unrelated custom provider.

Verify `/bin/bash -n` on the generated launcher, owner executable permissions, intended proxy URI and original `CODEX_HOME`. Installation does not launch the app. Finish active tasks, Quit / ⌘Q, then double-click the new launcher. Existing processes must exit before proxy inheritance can take effect.

Proxy environment support and Chromium flag behavior can vary by app version/transport. A generated launcher is not proof of successful model/Remote Control traffic. Verify a new turn and relevant logs after restart; if failures remain, diagnose that version rather than promise that every networking component honors the variables.

Official app documentation: [OpenAI desktop app](https://developers.openai.com/codex/app).
