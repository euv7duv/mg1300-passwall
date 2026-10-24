# MG1300 双内核版构建脚本（sing-box + xray）

组装 GL-MG1300 官固（OpenWrt 22.03.4 / mipsel_24kc）专用的 PassWall v1 离线包 —— **双内核版**，与 `../mg1300-singbox/` 的仅 sing-box 版分开，两者不要混用。当前版本 **v5**（一键脚本横幅会显示版本号）。

## 一键安装（路由器能联网时）

SSH 登录路由器后跑一行（脚本在仓库根目录）：自动下载离线包 `.tar.gz`、校验 sha256、解压到 /tmp 后**删掉下载包再安装**（装过仅 sing-box 版的可直接跑，已装的包自动跳过，只补 xray 部分）：

```sh
curl -fsSL https://raw.githubusercontent.com/euv7duv/mg1300-passwall/main/install-mg1300-dual.sh | sh
```

手动安装：下载 [Release mg1300-dual-26.10.16](https://github.com/euv7duv/mg1300-passwall/releases/tag/mg1300-dual-26.10.16) 的 `.run`，传到路由器 **/root**（不要放 /tmp，内存盘放不下解压）后 `chmod +x` 直接运行，全程离线。

## 内容

- PassWall 26.10.16 官方 22.03 构建 + sing-box 1.14.3（自编，标签 with_gvisor/with_quic/with_utls/with_clash_api/with_wireguard）+ xray-core 26.10.17 + xray-geodata 26.10.17。xray 两个 ipk 为 **tar 式打包**（22.03 的 opkg 不认 ar 式，会报 "Malformed package file"）。
- 其余依赖：GL 官方源的 userspace 包与 4 个 kmod（vermagic 对官固 5.10.176 内核）、ImmortalWrt 23.05 源的小工具；LuCI 装机时从设备 /etc/luci_ipks 取（27 个 ipk 共 536KB）。
- `extras/99-passwall-autostart`：可选的中继感知自启钩子（见下「自启」）。
- Release 附带 `geoview-softfloat-mipsle`：自编软浮点版 geoview 0.2.8（见下「geoview」），一键安装成功后会自动顺带装上；手动装.run 的用户可自行下载放到 /usr/bin 并 +x。

## 协议覆盖（对 full.sh 的 9 组合为 8/9）

- Sing-Box 类型：VLESS+REALITY+Vision、Trojan+REALITY、SS-2022、VMess+WS、Hysteria2、TUIC、AnyTLS+REALITY，外加 WireGuard / Hysteria v1 / SSH / Snell / Socks / HTTP。
- Xray 类型：以上之外再加 **VLESS+XHTTP+REALITY**。
- 不行：NaiveProxy（sing-box 自编版没 with_naive_outbound 标签）、SSR（没带 ssr-libev）。

## 自启（默认关闭，是特性不是 bug）

opkg 装包时默认会把 PassWall 设为开机自启，且 luci-app-passwall 的 uci-defaults 会注册防火墙 include —— 在官固上，**光是装上、从未启用，重启后中继就断了**（真机实测）。所以 installer 收尾无条件 `disable` 两个服务。想要「开机自动连」又不伤中继，用包里 `extras/99-passwall-autostart`：拷到 `/etc/hotplug.d/iface/` 后，它等中继 wwan 起来、且 PassWall 主开关为开时才延迟 20 秒拉起 PassWall（中继先行、代理随后，真机终验通过）。删掉该文件即恢复全手动。

## geoview（组件页显示/「不适合当前设备」的真因）

geoview 官方的 linux-mipsle 版是**硬浮点**编译，MT7621 上一运行就 `Illegal instruction`，PassWall 的版本探针读不到版本号，于是永远判「不适合当前设备」——与网络、与下载是否完整无关，换任何官方版本（含 0.2.6）都一样。本 Release 附带的 `geoview-softfloat-mipsle` 是从官方 0.2.8 源码以 `GOMIPS=softfloat` 自编的（与能跑的 sing-box 同为软浮点），真机验证 `-version` 正常输出、组件页能认出。**装好后不要再点组件页的「检查更新」**，它会去抓官方硬浮点版，必然失败（已装的软浮点版不会被失败的更新覆盖）。

## 本地组装

把 18 个 ipk 放进 `dl/`（清单见 build.sh），运行 `./build.sh`，产出 `.run` 与同内容 `.tar.gz` 及各自 sha256。

## What v5 fixed（v1–v4 的失败教训，全部来自真机）

1. **ipk 打包格式**：xray 两个 ipk 曾用 ar 式打包，被 22.03 的 opkg 拒（"Malformed package file"）。改 tar 式（成员./debian-binary、./control.tar.gz、./data.tar.gz）。
2. **空间门槛别写死**：v1 的固定 50MB 门槛被.run 本身占的空间误拦，全新机也装不了。
3. **空间「加回」不可靠**：v2 按挂载点把包体积加回可用空间，对续装场景过严，误杀。
4. **「装完才释放的空间」不能算作「装时可用」**：v3 的需求 ×1.15＋加回模型在全新机上装到 0KB，倒在最后一个 LuCI 包。v5 的需求模型（未装 ipk 体积 ×1.6＋4MB，LuCI 另计 1MB）是真机量出来的：全套实际写入约 43.7MB，ipk 总体积约 27.3MB。
5. **运行中的脚本删不掉自己**：v4 在脚本内 `rm` 自己的.run，因 shell 还占着文件句柄，空间根本没释放，空间检查看到的仍是包在盘时的数字；且进程退出后文件其实已删，「kept for retry」的提示也成了假话。v5 两条入口都改成「删包的进程不是包本身」：.run 用 /tmp 跳板重执行再删原件（并显式关闭继承的文件句柄）；一键改下.tar.gz，先解压到 /tmp、删下载、再跑解压出的 installer。
6. **默认自启伤中继**：见上「自启」。v5 收尾无条件 disable，并提供中继感知钩子作为可选解法。
7. **验证必须原样跑真脚本**：v1–v4 的缺陷全部由真机暴露，因为沙箱里只验过打桩逻辑，没原样执行过.run/一键。v5 发布前在高保真测试台（72MB tmpfs 冒充 /overlay + 按真实体积消耗的假 opkg）原样执行两条入口、三场景（全新/半装/真满）全过才发布；其中全新场景把.run 放在 /overlay 内运行 —— 自删若失效，空间检查必然误拦，场景本身就是探针。
8. **脚本要有版本号横幅**：出过「用户那侧 CDN 边缘缓存还给旧脚本、新旧无从分辨」的事。v5 的 installer 与一键第一行都打印版本号。
9. **GFW 模式下百度被 NXDOMAIN**（installer v5.1 / 一键 v5.2 追加）：真机发现开 GFW 列表模式时 www.baidu.com 被 ChinaDNS-NG 回 NXDOMAIN——它的 CNAME 目标 a.shifen.com 不在任何内置名单里，跨组判定把答案丢了。installer 收尾把 `baidu.com`、`shifen.com` 两行幂等写入用户直连名单 `/etc/passwall/rules/direct_host`（默认启用、优先级最高、只走直连 DNS），GFW 模式与百度从此共存；不需要这两行可装后自行删除。

## 占用

全套装完约 43.7MB 实际写入；全新机（/overlay 共 72.6MB）装后余约 26MB。geoview 软浮点版另占约 7MB（可选）。
