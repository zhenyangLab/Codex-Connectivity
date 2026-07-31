# Codex Proxy Shortcut

一个面向 Windows Codex / ChatGPT Desktop 的可复用 Skill，用于：

- 解决代理环境下每次请求先出现 `Connecting/Reconnecting 1/5 ... 5/5` 的问题。
- 强制 Codex 直接使用 HTTP/SSE，跳过失败的 Responses WebSocket 重试。
- 创建只让 Codex 进程树使用本地 HTTP 代理的桌面快捷方式。
- 在 Microsoft Store 更新 Codex 后自动识别新的 AppX 安装路径。

## 原理

部分代理可以正常转发 HTTPS/SSE，但无法稳定转发 Codex Responses WebSocket。Codex 会先尝试 WebSocket，连续失败五次后才回退到 HTTP，因此界面会反复显示：

```text
Reconnecting... 1/5
...
Reconnecting... 5/5
```

本 Skill 使用两层配置：

1. 在 Codex 配置中创建 ChatGPT 登录兼容的 HTTP/SSE provider，并设置 `supports_websockets = false`。
2. 通过桌面快捷方式启动 Codex，仅向该进程及其子进程注入代理变量和 Chromium 代理参数。

## 安全边界

本 Skill 不会：

- 修改 Windows 系统代理、WinINET 或 WinHTTP。
- 创建持久化的用户或系统代理环境变量。
- 修改注册表代理项、路由或防火墙。
- 修改 `%USERPROFILE%\.ssh\config`。
- 自动删除或关闭 Remote Control。
- 自动关闭或重启正在运行的 Codex。

修改 `config.toml` 前会生成带时间戳的备份。

## 系统要求

- Windows 10 或 Windows 11。
- Microsoft Store 安装的 `OpenAI.Codex`。
- Windows PowerShell 5.1 或更高版本。
- 已登录的 Codex / ChatGPT 账号。
- 可用的本地 HTTP 代理，例如 `127.0.0.1:12450`。

## 安装为 Codex Skill

把仓库克隆到个人 Skill 目录：

```powershell
git clone https://github.com/zhenyangLab/codex-proxy.git `
  "$env:USERPROFILE\.codex\skills\codex-proxy-shortcut"
```

重新打开 Codex 后，可以直接请求：

```text
使用 $codex-proxy-shortcut，给 Windows Codex 配置 127.0.0.1:12450，
解决五次 Connecting，并创建桌面快捷方式。
```

## 手动运行安装脚本

先执行只读预演：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\install-codex-proxy-shortcut.ps1" `
  -ProxyHost "127.0.0.1" `
  -ProxyPort 12450 `
  -WhatIf
```

确认预演目标正确后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\install-codex-proxy-shortcut.ps1" `
  -ProxyHost "127.0.0.1" `
  -ProxyPort 12450
```

默认生成：

```text
桌面快捷方式：
%USERPROFILE%\Desktop\Codex-HTTP-Proxy-12450.lnk

启动脚本：
D:\Codex\codex-proxy-shortcuts\127.0.0.1-12450\Launch-Codex-With-Proxy.ps1
```

如果代理暂时没有运行，但需要预先创建文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\install-codex-proxy-shortcut.ps1" `
  -ProxyHost "127.0.0.1" `
  -ProxyPort 12450 `
  -SkipProxyCheck
```

## 使用注意

创建快捷方式后：

1. 完全退出 Codex / ChatGPT，包括后台进程。
2. 确认本地 HTTP 代理已经监听指定端口。
3. 通过新快捷方式启动 Codex。
4. 发起一个新请求，确认不再出现固定的五次重连。

如果日志目标是：

```text
codex_app_server_transport::transport::remote_control::websocket
```

这是 Remote Control 的独立连接，不是普通模型请求的五次 WebSocket 回退。本 Skill 不会自动修改它。

## 文件结构

```text
codex-proxy-shortcut/
├── README.md
├── SKILL.md
├── agents/
│   └── openai.yaml
├── references/
│   └── five-connecting.md
└── scripts/
    └── install-codex-proxy-shortcut.ps1
```

## 相关资料

- [Codex configuration reference](https://developers.openai.com/codex/config-reference/)
- [Responses WebSocket retries before HTTP fallback](https://github.com/openai/codex/issues/19821)
- [HTTP-only provider workaround](https://github.com/openai/codex/issues/22634)
