#!/bin/sh
# Assemble the v5 offline packages (dual-core: sing-box + xray) for GL-MG1300
# stock firmware (OpenWrt 22.03.4 / mipsel_24kc).
# Expects all ipks in ./dl (see README for provenance) plus install.sh,
# stub.sh and extras/ in this directory.
set -e
cd "$(dirname "$0")"
NAME="passwall_26.10.16-dual_mipsel_24kc_openwrt-22.03-mg1300"
rm -rf payload "${NAME}.run" "${NAME}.tar.gz"
mkdir -p payload/ipks payload/extras
cp install.sh payload/
cp extras/99-passwall-autostart payload/extras/
IPKS="
kmod-nf-socket_5.10.176-1_mipsel_24kc.ipk
kmod-nft-socket_5.10.176-1_mipsel_24kc.ipk
kmod-nft-tproxy_5.10.176-1_mipsel_24kc.ipk
kmod-netlink-diag_5.10.176-1_mipsel_24kc.ipk
libyaml_0.2.5-1_mipsel_24kc.ipk
lyaml_6.2.7-2_mipsel_24kc.ipk
coreutils-base64_9.0-2_mipsel_24kc.ipk
coreutils-nohup_9.0-2_mipsel_24kc.ipk
chinadns-ng_2025.08.09-1_mipsel_24kc.ipk
dns2socks_2.1-2_mipsel_24kc.ipk
ipt2socks_1.1.4-2_mipsel_24kc.ipk
microsocks_1.0.5-1_mipsel_24kc.ipk
tcping_2020-07-04-db910183-1_mipsel_24kc.ipk
sing-box_1.14.3-1_mipsel_24kc.ipk
xray-core_26.10.17-1_mipsel_24kc.ipk
xray-geodata_26.10.17-1_all.ipk
luci-app-passwall_26.10.16_all.ipk
luci-i18n-passwall-zh-cn_26.10.16_all.ipk
"
for f in $IPKS; do
	if [ ! -f "dl/$f" ]; then
		echo "MISSING dl/$f" >&2
		exit 1
	fi
	cp "dl/$f" payload/ipks/
done
chmod +x payload/install.sh payload/extras/99-passwall-autostart
tar --numeric-owner --owner=0 --group=0 -czf payload.tar.gz -C payload .
cat stub.sh payload.tar.gz > "${NAME}.run"
chmod +x "${NAME}.run"
cp payload.tar.gz "${NAME}.tar.gz"
rm -rf payload payload.tar.gz
ls -la "${NAME}.run" "${NAME}.tar.gz"
sha256sum "${NAME}.run" "${NAME}.tar.gz"
