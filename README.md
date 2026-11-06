# Codex Connectivity

为 **Windows 与 macOS** 上的 Codex / ChatGPT Desktop 创建进程级代理启动器，帮助排查反复重连和 Remote Control 连接失败，同时保留现有 `CODEX_HOME` 和历史记录。

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)
![macOS](https://img.shields.io/badge/macOS-supported-333333)
![Proxy Scope](https://img.shields.io/badge/Proxy-Process--scoped-22A699)

## 使用时先问什么？

调用 skill 后，会先主动列出选项：

**1. 这次要配置的电脑是什么系统？**

- Windows 10 / 11
- macOS（Mac）
- 不确定 / 其他系统

**2. 本地代理的 HTTP 或 Mixed（混合）端口是多少？**

- 我知道，输入端口（1–65535）
- 不知道，帮我查看
- 还没有代理软件 / 本地代理

不知道时，继续选择查看代理软件设置、只读检查本机，或提供软件名按界面引导。已有明确答案时不会重复询问；不会把示例端口当作实际配置。

## 代理端口一般在哪里看？

优先打开代理客户端，进入 **设置 / 网络 / 端口 / 入站设置**，查找 **HTTP Port** 或 **Mixed Port / 混合端口**。菜单随软件版本有所不同。

- Clash 系客户端：查看 HTTP 或混合端口；配置字段一般为 `port` 或 `mixed-port`。
- v2rayN / v2rayU 等：查看本地监听或入站配置中的 HTTP / 混合端口，部分版本也在状态栏显示。
- Mac：系统设置 → 网络 → 当前连接 → 详细信息 → 代理，可查看已有网页代理地址和端口。[Apple 设置说明](https://support.apple.com/guide/mac-help/mchlp2591/mac)
- Windows：设置 → 网络和 Internet → 代理，可查看已有手动代理地址和端口。

**无需为了查看端口启用系统代理。** 系统代理未开启时，系统设置中的值可能为空或过期，以客户端当前配置为准。需要的是本机 HTTP / Mixed 端口，不能直接用节点服务器、SOCKS-only 或控制面板/API 的端口。详见 [端口查找指南](references/proxy-port.md)。

## 安装为 skill

Windows（PowerShell）：

```powershell
$skillRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
git clone https://github.com/zhenyangLab/Codex-Connectivity.git `
  (Join-Path $skillRoot 'skills\codex-connectivity')
```

macOS（终端）：

```bash
git clone https://github.com/zhenyangLab/Codex-Connectivity.git \
  "${CODEX_HOME:-$HOME/.codex}/skills/codex-connectivity"
```

若目标目录已经存在，请在原目录更新，避免覆盖本地修改。重新打开应用后调用：

```text
使用 $codex-connectivity 帮我配置代理。
先让我选择电脑系统和代理端口；不知道端口时引导我查看。
保留历史记录，只为 Codex 创建进程级代理启动器。
```

## 平台支持

| 项目 | Windows | macOS |
|---|---|---|
| 安装器 | PowerShell `.ps1` | 系统 Bash `.sh`，无需 Homebrew / Python |
| 桌面入口 | `.lnk` 快捷方式 | 可双击的 `.command` 文件 |
| 应用定位 | 每次查找最新 `OpenAI.Codex` AppX | 检查 `/Applications`、`~/Applications`，读取应用包实际可执行文件 |
| 更新适配 | 自动查找新版包，刷新图标 | 应用包路径不变时，每次重新读取内部可执行文件 |
| 历史记录 | 保留同一 `CODEX_HOME` | 保留同一 `CODEX_HOME` |
| 旧 provider 修复 | 备份后自动修复旧版托管配置 | 检测到旧配置时停止，先检查、备份并单独修复 |

Linux 暂不支持。Mac 上安装了多个候选应用时，需要指定目标应用。应用自身必须支持当前电脑硬件。

## 手动运行

以下端口 `7897` **仅为示例**，请替换为确认过的 HTTP / 混合端口。运行命令前进入本项目目录。

Windows：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\install-codex-proxy-shortcut.ps1" `
  -ProxyHost "127.0.0.1" -ProxyPort 7897 -WhatIf
```

移除 `-WhatIf` 后生成文件。默认位置：

```text
%LOCALAPPDATA%\Codex\codex-proxy-shortcuts\127.0.0.1-7897\Launch-Codex-With-Proxy.ps1
桌面\Codex-HTTP-Proxy-7897.lnk
```

macOS：

```bash
bash ./scripts/install-codex-proxy-shortcut.sh \
  --proxy-host 127.0.0.1 --proxy-port 7897 --dry-run
```

移除 `--dry-run` 后生成 `~/Desktop/Codex-HTTP-Proxy-7897.command`。需要指定应用时添加：

```bash
--app-path "/Applications/Codex.app"
```

也支持目标 `ChatGPT.app`，以实际安装为准。多应用共存时不能自动猜测；应用移动或改名后重新安装启动器。`.command` 在终端中执行，应用运行期间终端窗口可能保持打开。

两平台均提供离线生成选项（Windows：`-SkipProxyCheck`；Mac：`--skip-proxy-check`），但启动器运行时仍检查端口。端口监听检查不能证明它是 HTTP 代理，更不能证明 WebSocket 可用。

## 生成以后如何验证？

1. 先完成当前任务，完全退出应用（Mac 用 ⌘Q，关闭窗口不等于退出）。安装器不会重启应用。
2. 确认本地代理客户端已启动，通过新建的专用桌面入口打开应用。
3. 确认原有历史任务显示正常，发起一个新请求检查重连情况。
4. 需要 Remote Control 时，在应用的连接设置中手动开启允许连接，并检查新日志及手机连接。

模型 Responses 与 Remote Control 是不同连接路径。启动器为进程树设置大写/小写 HTTP、HTTPS、WS、WSS、ALL、NO proxy 变量，并传递 Chromium 代理参数和 `--disable-quic`。实际支持情况随应用版本、传输组件和代理节点而变；生成文件或 HTTP 请求成功不代表两条路径都已验证。

## 配置与历史记录

启动器保留安装时检查过的 `CODEX_HOME`（未设置时是用户目录的 `.codex`），不会创建另一份历史目录，也不通过切换自定义 provider 强制传输方式。

旧版 Windows skill 曾选择 `codex_proxy_http`，可能让原 `openai` 任务看起来消失。Windows 安装器会在备份后移除旧托管块并恢复旧选择。Mac 安装器遇到这些标记会停止，不会用文本匹配直接改写 TOML。任何修复都不编辑 session JSONL、线程 SQLite 数据库或账号/配对数据。

## 代理范围与边界

环境变量只属于启动器和其创建的应用进程树。其他应用保持既有网络设置；如果用户原先已经开启系统代理或 TUN，它们仍可能受原配置影响。

本项目不更改系统代理、WinHTTP、注册表代理项、路由、防火墙、持久环境变量、shell 启动文件或 `launchctl` 登录会话变量，不修改 SSH 配置或签名应用包内容。默认只允许同机回环地址；远端代理需明确批准后启用相应选项。本 skill 不提供代理服务，也不处理 SSH 登录服务器。

## 开发验证

macOS（使用临时假应用和本地监听端口，不启动实际 Codex）：

```bash
python3 -m unittest discover -s tests -p 'test_macos*.py' -v
bash -n scripts/install-codex-proxy-shortcut.sh
```

Windows（需要已安装 Store 应用）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test-installer.ps1
```

平台细节见 [macOS](references/macos.md)、[Windows](references/windows.md) 和 [连接诊断](references/connectivity-diagnosis.md)。官方应用信息见 [OpenAI 文档](https://developers.openai.com/codex/app)。
