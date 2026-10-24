#!/bin/sh
# One-click installer v5.3: PassWall v1 dual-core (sing-box + xray) for GL.iNet GL-MG1300 stock firmware 4.10.x.
# Downloads the offline package (.tar.gz) from the GitHub release, verifies its
# sha256, extracts it to /tmp (RAM), deletes the download for real, then runs
# the extracted installer. The install itself is fully offline.
#
# Why v5 looks the way it does (v1-v4 failed on real hardware, see README
# "What v5 fixed"): a script cannot free its own file while it runs, so the
# download is always deleted by a process that is not the download; the
# version banner below exists so a stale CDN-cached copy of this script is
# recognizable at a glance; and the optional geoview step at the end ships a
# soft-float build because the official geoview binaries are hard-float and
# die with "Illegal instruction" on the MT7621.
#
# Usage (SSH into the router first):
#   curl -fsSL https://raw.githubusercontent.com/euv7duv/mg1300-passwall/main/install-mg1300-dual.sh | sh
#   or: wget -qO- https://raw.githubusercontent.com/euv7duv/mg1300-passwall/main/install-mg1300-dual.sh | sh
# Mirrors/tests may override the download locations with PW_PKG_URL / PW_GEOVIEW_URL.

FILE="passwall_26.10.16-dual_mipsel_24kc_openwrt-22.03-mg1300.tar.gz"
URL="${PW_PKG_URL:-https://github.com/euv7duv/mg1300-passwall/releases/download/mg1300-dual-26.10.16/${FILE}}"
SHA256="ee32546f4efd43756ec9a19156ba25b04e07beeee8559690d90e51f0832e3ba1"
GEOVIEW_URL="${PW_GEOVIEW_URL:-https://github.com/euv7duv/mg1300-passwall/releases/download/mg1300-dual-26.10.16/geoview-softfloat-mipsle}"
GEOVIEW_SHA256="dea7b3047bde2d7446a1a44bd4838bd46c44298e82cbceccb6ee05c973ec33ee"
DEST="/root/${FILE}"

echo "== PassWall v1 dual-core (sing-box + xray) for GL-MG1300 stock firmware - one-click v5.3 =="

if [ "$(id -u)" != "0" ]; then
	echo "ABORT: run as root."
	exit 1
fi

# Quick platform pre-check (the package installer checks again, strictly).
if [ -f /etc/openwrt_release ]; then
	. /etc/openwrt_release
	if [ "${DISTRIB_ARCH}" != "mipsel_24kc" ] || [ "${DISTRIB_RELEASE}" != "22.03.4" ]; then
		echo "ABORT: this one-click is for GL-MG1300 stock firmware (OpenWrt 22.03.4 / mipsel_24kc) only."
		echo "Detected: ${DISTRIB_DESCRIPTION}"
		exit 1
	fi
fi

download() {
	# download <url> <dest>
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$2" "$1"
	else
		return 1
	fi
}

check_sha() {
	# check_sha <expected> <file>
	command -v sha256sum >/dev/null 2>&1 || return 0
	echo "$1  $2" > /tmp/.pw-sha.$$
	if sha256sum -c /tmp/.pw-sha.$$ >/dev/null 2>&1; then
		rm -f /tmp/.pw-sha.$$
		return 0
	fi
	rm -f /tmp/.pw-sha.$$
	return 1
}

# The download lands on the overlay (via /root): make sure it can even fit
# before starting, and say so honestly - a space failure must not masquerade
# as a network failure (v5 rig test, "nearly full" scenario).
ROOTFREE="$(df /root 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${ROOTFREE}" ] && [ "${ROOTFREE}" -lt 35840 ]; then
	echo "ABORT: only ${ROOTFREE}KB free on /root - the ~33MB package download would not fit."
	echo "Free some space on the router first, then retry."
	exit 1
fi

echo "Downloading ${FILE} ..."
if ! download "${URL}" "${DEST}"; then
	rm -f "${DEST}"
	echo "ABORT: download failed (network problem, or the download did not fit)."
	echo "Check the router's internet connection and free space, or download"
	echo "the package on a computer and install offline (see README)."
	exit 1
fi

if ! check_sha "${SHA256}" "${DEST}"; then
	echo "ABORT: sha256 mismatch - the downloaded file is corrupted, deleting it."
	rm -f "${DEST}"
	exit 1
fi
echo "sha256 OK"

# Extract to /tmp (RAM), delete the download, THEN install: the installer's
# free-space check must see the overlay without the ~33MB package on it, and
# deleting from inside a running script would not free the space in time.
WORK="$(mktemp -d /tmp/pw-dual.XXXXXX)" || {
	echo "ABORT: cannot create a temp directory."
	exit 1
}
if ! tar -xzf "${DEST}" -C "${WORK}"; then
	echo "ABORT: package extract failed - the download is corrupted."
	rm -rf "${WORK}"
	exit 1
fi
rm -f "${DEST}"
echo "Package extracted; the download was deleted to free overlay space."
cd "${WORK}" || exit 1
chmod +x install.sh
./install.sh
RC=$?
cd /
rm -rf "${WORK}"

# Optional component: geoview (used by PassWall's geosite rule tools). The
# official builds are hard-float and crash on the MT7621, so this fetches the
# soft-float build published with this release. Best-effort only: a failure
# here never fails the install.
if [ "${RC}" = "0" ]; then
	if [ -x /usr/bin/geoview ] && /usr/bin/geoview -version >/dev/null 2>&1; then
		echo "geoview: already present and working, skipped."
	elif download "${GEOVIEW_URL}" /tmp/geoview-softfloat.$$ && check_sha "${GEOVIEW_SHA256}" /tmp/geoview-softfloat.$$; then
		cp /tmp/geoview-softfloat.$$ /usr/bin/geoview
		chmod +x /usr/bin/geoview
		rm -f /tmp/geoview-softfloat.$$
		if /usr/bin/geoview -version >/dev/null 2>&1; then
			echo "geoview: installed soft-float build ($(/usr/bin/geoview -version))."
		else
			echo "WARN: geoview installed but does not run on this device; PassWall works without it."
		fi
	else
		rm -f /tmp/geoview-softfloat.$$
		echo "WARN: optional geoview download failed; PassWall works without it (see README)."
	fi
fi

if [ "${RC}" = "0" ]; then
	echo "Done. (Re-run this one-click to reinstall.)"
else
	echo "Installer exited with code ${RC}; re-run this one-click to retry (it downloads the package again)."
fi
exit ${RC}
