#!/bin/sh
# PassWall v1 dual-core (sing-box + xray) offline installer v5.1 for GL.iNet GL-MG1300 stock firmware.
# Target: OpenWrt 22.03.4 / mipsel_24kc / kernel 5.10.176 (GL stock 4.10.x).
# Everything installs from local ipks in this directory - no network, no opkg update.
#
# Design rules carried out of the v1-v4 failures (see README "What v5 fixed"):
#  - The free-space check only ever trusts space that is free RIGHT NOW.
#    Nothing is "added back": not the package file (both entry paths delete
#    it before this script runs), not anything that would free up later.
#    v3's add-back passed its own check and still filled a fresh router to
#    0KB mid-install; the demand model below is the one that survived
#    contact with real hardware.
#  - PassWall's autostart is disabled at the end, unconditionally: opkg's
#    default postinst enables it, and on GL stock firmware an unattended
#    boot-time start can disturb the repeater.
set -u
cd "$(dirname "$0")" || exit 1
IPKDIR="."
[ -d ./ipks ] && IPKDIR="./ipks"

echo "== PassWall v1 dual-core (sing-box + xray) for GL-MG1300 stock firmware - installer v5.1 =="

# --- platform guard ---
. /etc/openwrt_release
if [ "$DISTRIB_ARCH" != "mipsel_24kc" ] || [ "$DISTRIB_RELEASE" != "22.03.4" ]; then
	echo "ABORT: this package targets OpenWrt 22.03.4 / mipsel_24kc (GL-MG1300 stock)."
	echo "Detected: $DISTRIB_DESCRIPTION"
	if [ "${FORCE:-0}" != "1" ]; then
		echo "Re-run with FORCE=1 to override (kmods will likely fail on a wrong kernel)."
		exit 1
	fi
	echo "FORCE=1 given, continuing anyway..."
fi
KVER="$(uname -r)"
[ "$KVER" != "5.10.176" ] && echo "WARN: running kernel is $KVER; bundled kmods are for 5.10.176 (GL build 0098f055f625808a4da8751910d9991b)."

installed() { opkg list-installed 2>/dev/null | grep -q "^$1 - "; }

# --- free space guard ---
# Demand = what is actually left to install: sum the file sizes of the
# bundled ipks whose packages are not installed yet, x1.6 headroom (the
# full set's measured on-disk write was ~43.7MB from ~27.3MB of ipk files),
# +4MB slack; +1MB if the GL LuCI stash still has to be installed (its 27
# ipks total 536KB, measured). Measured free space is whatever df reports
# at this moment - the download was already deleted by the entry path.
NEEDKB=4096
for f in "$IPKDIR"/*.ipk; do
	[ -f "$f" ] || continue
	pname="$(basename "$f")"
	pname="${pname%%_*}"
	if ! installed "$pname"; then
		sz="$(du -k "$f" | awk '{print $1}')"
		[ -n "$sz" ] && NEEDKB=$((NEEDKB + sz * 160 / 100))
	fi
done
installed luci-base || NEEDKB=$((NEEDKB + 1024))
FREEKB="$(df /overlay | awk 'NR==2 {print $4}')"
if [ -z "$FREEKB" ]; then
	echo "WARN: could not read /overlay free space; skipping the space check."
elif [ "$FREEKB" -lt "$NEEDKB" ]; then
	echo "ABORT: /overlay free space is ${FREEKB}KB, but the remaining packages need ~${NEEDKB}KB."
	echo "Free some space on the router first, then retry."
	exit 1
fi
echo "Overlay free: ${FREEKB}KB (remaining packages need ~${NEEDKB}KB)"
inst() {
	# inst <ipk-glob> <package-name>
	if installed "$2"; then
		echo "skip (already installed): $2"
		return 0
	fi
	f="$(ls $IPKDIR/$1 2>/dev/null | head -n1)"
	if [ -z "$f" ]; then
		echo "WARN: ipk not found for $2 ($1)"
		return 1
	fi
	echo "install: $2"
	opkg install --force-depends "$f" || echo "WARN: opkg reported an error for $2"
}

# --- 1. LuCI base: GL stock firmware keeps it in /etc/luci_ipks, installed on demand ---
if ! installed luci-base; then
	if [ -d /etc/luci_ipks ]; then
		echo "LuCI not present - installing GL bundled LuCI set from /etc/luci_ipks ..."
		opkg install --force-depends /etc/luci_ipks/*.ipk || true
	else
		echo "WARN: luci-base missing and /etc/luci_ipks not found."
		echo "      Enable LuCI from the GL panel first, then re-run this installer."
	fi
fi
# The two LuCI libs PassWall needs also live in the stash:
if ! installed luci-compat; then
	ls /etc/luci_ipks/luci-compat_*.ipk >/dev/null 2>&1 && opkg install --force-depends /etc/luci_ipks/luci-compat_*.ipk || true
fi
if ! installed luci-lib-jsonc; then
	ls /etc/luci_ipks/luci-lib-jsonc_*.ipk >/dev/null 2>&1 && opkg install --force-depends /etc/luci_ipks/luci-lib-jsonc_*.ipk || true
fi

# --- 2. bundled packages, dependency order ---
inst "kmod-nf-socket_*.ipk"        kmod-nf-socket
inst "kmod-nft-socket_*.ipk"       kmod-nft-socket
inst "kmod-nft-tproxy_*.ipk"       kmod-nft-tproxy
inst "kmod-netlink-diag_*.ipk"     kmod-netlink-diag
inst "libyaml_*.ipk"               libyaml
inst "lyaml_*.ipk"                 lyaml
inst "coreutils-base64_*.ipk"      coreutils-base64
inst "coreutils-nohup_*.ipk"       coreutils-nohup
inst "chinadns-ng_*.ipk"           chinadns-ng
inst "dns2socks_*.ipk"             dns2socks
inst "ipt2socks_*.ipk"             ipt2socks
inst "microsocks_*.ipk"            microsocks
inst "tcping_*.ipk"                tcping
inst "sing-box_*.ipk"              sing-box
inst "xray-geodata_*.ipk"          xray-geodata
inst "xray-core_*.ipk"             xray-core
inst "luci-app-passwall_*.ipk"     luci-app-passwall
inst "luci-i18n-passwall-zh-cn_*.ipk" luci-i18n-passwall-zh-cn

# --- 3. wrap up ---
# PassWall must not come up on its own after a fresh install: opkg's default
# postinst rc-enables its init scripts, and luci-app-passwall's uci-defaults
# also register a firewall include. On GL stock firmware an unattended
# PassWall start can disturb the repeater's forwarding (observed on a real
# MG1300: repeater up before install, dead after, PassWall never enabled).
# Disable the autostart; the user starts PassWall from LuCI when they want
# it, or installs the optional relay-aware hook from extras/ (see README).
/etc/init.d/passwall disable 2>/dev/null
/etc/init.d/passwall_server disable 2>/dev/null
# Baidu/GFW coexistence fix (2026-10-23, observed on a real MG1300): with the
# GFW list enabled, ChinaDNS-NG returns NXDOMAIN for www.baidu.com - its
# CNAME target a.shifen.com is in no built-in list, and the cross-group
# verdict drops the answer. Pin baidu.com and shifen.com in the user direct
# list (enabled by default, highest priority, resolved by the direct DNS
# only). Idempotent; a failure here only warns - the install has succeeded.
DH=/etc/passwall/rules/direct_host
mkdir -p /etc/passwall/rules 2>/dev/null
for d in baidu.com shifen.com; do
	if ! grep -qx "$d" "$DH" 2>/dev/null; then
		echo "$d" >> "$DH" 2>/dev/null || echo "WARN: could not add $d to $DH"
	fi
done
echo "Direct list seeded: baidu.com, shifen.com (keeps Baidu working in GFW-list mode)."
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null

echo ""
echo "Overlay after install: $(df /overlay | awk 'NR==2 {print $4}')KB free"
if installed luci-app-passwall && [ -x /usr/bin/sing-box ] && [ -x /usr/bin/xray ]; then
	echo "DONE: PassWall $(opkg list-installed luci-app-passwall | awk '{print $3}') with $(/usr/bin/sing-box version | head -n1) + $(/usr/bin/xray version | head -n1)"
	echo "Open LuCI -> Services -> PassWall. Dual-core build: both the sing-box"
	echo "and the xray core are installed - Sing-Box-type and Xray-type nodes"
	echo "both work (XHTTP goes through the Xray type)."
	echo "NOTE: PassWall autostart is OFF on purpose (relay-safe). It will not"
	echo "start by itself at boot; enable it in LuCI when you want it, or add"
	echo "the optional relay-aware autostart hook from the extras/ folder."
else
	echo "FINISHED WITH WARNINGS - check the WARN lines above."
fi
