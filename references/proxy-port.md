# 查找本地代理端口

需要的是代理软件在**当前电脑**监听的 **HTTP** 或 **Mixed / 混合**端口，不是节点服务器端口、订阅链接端口、SOCKS-only 端口或控制面板/API 端口。不同版本的菜单名称可能变化，以软件实际显示为准。不要把 7890、7897、10809、12450 等示例当作用户配置。

## 首选：代理软件

打开正在使用的客户端，在“设置 / 网络 / 端口 / 入站设置”中查找 `HTTP Port`、`Mixed Port`、`HTTP 代理端口` 或 `混合端口`。

- Clash 系客户端（如 Clash Verge Rev、ClashX）：查看设置中的端口；若界面没有展示，可只读查看当前生效配置中的 `port` 或 `mixed-port`。`socks-port` 不能直接代替，`external-controller` 是管理接口。
- v2rayN / v2rayU 等：查看本地监听或入站设置中的 HTTP / 混合端口，部分版本也会在状态栏显示。不要仅根据软件名推断端口。
- 其他客户端：让用户提供软件名和版本，再按实际界面引导。只有 TUN/VPN 且没有 HTTP 监听时，这套启动器暂不能使用。

同机地址通常是 `127.0.0.1`。例如软件显示 `Mixed Port: 7897`，本地 HTTP 地址可填写 `http://127.0.0.1:7897`；数字仅为示例。

## macOS：只读检查

系统设置 → 网络 → 当前连接（Wi-Fi / 以太网）→ 详细信息 → 代理，可查看已配置的网页代理（HTTP）或安全网页代理（HTTPS）的服务器和端口。**不用打开开关或保存更改**。系统代理关闭时这里可能为空或过期，仍以客户端当前配置为准。

终端只读检查：

```bash
scutil --proxy
lsof -nP -iTCP -sTCP:LISTEN
```

前者的 `HTTPPort` / `HTTPSPort` 是系统当前报告的值，后者显示进程名和监听地址。只展示有关候选项，不把所有监听端口直接当作代理。

参考：[Apple：更改 Mac 上的代理设置](https://support.apple.com/guide/mac-help/mchlp2591/mac)。

## Windows：只读检查

可在 设置 → 网络和 Internet → 代理 中查看已有手动代理地址/端口；不需要启用系统代理。也可以只读检查：

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer
Get-NetTCPConnection -State Listen |
  Select-Object LocalAddress, LocalPort, OwningProcess
# 对候选 OwningProcess 查询名称：Get-Process -Id <PID>
```

若系统没有配置代理，直接看代理软件设置最可靠。候选项找到后，询问用户确认 **地址 + HTTP/Mixed 端口**，再进行安装。
