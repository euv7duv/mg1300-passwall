#!/bin/sh
# Self-extracting offline installer v5.0: PassWall v1 dual-core (sing-box + xray) for GL-MG1300 stock fw.
# The payload (install.sh + ipks/) is a tar.gz appended after the PAYLOAD marker line.
#
# The trampoline below exists because of a v4 failure: a running shell script
# cannot free its own file - the file's blocks stay allocated until the
# process exits, so v4's "extract, rm $SELF, then install" deleted nothing in
# practice and the installer's space check aborted on fresh routers. Here the
# stub first re-executes a copy of itself out of /tmp; after that, no process
# holds the original file open (any inherited descriptor pointing at it is
# closed explicitly), so deleting it genuinely frees its ~33MB BEFORE the
# installer measures free space.
SELF="$0"
if [ -z "${PW_TRAMP:-}" ]; then
	case "$SELF" in
	/tmp/*) ;;
	*)
		T="/tmp/.pw-stub.$$"
		if cp "$SELF" "$T" 2>/dev/null; then
			chmod +x "$T"
			PW_TRAMP=1 exec sh "$T" "$SELF"
		fi
		echo "WARN: could not stage a /tmp copy of this script; continuing in place."
		;;
	esac
fi
ORIG="${1:-$SELF}"
TMPD="$(mktemp -d /tmp/pw-dual.XXXXXX)" || exit 1
trap 'rm -rf "$TMPD"' EXIT INT TERM
LINE="$(awk '/^__PAYLOAD_BELOW__$/ {print NR + 1; exit 0}' "$ORIG")"
if [ -z "$LINE" ]; then
	echo "ABORT: payload marker not found - the .run file is corrupted."
	exit 1
fi
tail -n +"$LINE" "$ORIG" | tar -xz -C "$TMPD" || { echo "ABORT: payload extract failed."; exit 1; }
# Close any descriptor this process inherited that still points at the
# original file (a script fd that survived the re-exec would keep the
# file's blocks allocated even after unlink).
for f in /proc/self/fd/*; do
	t="$(readlink "$f" 2>/dev/null)" || continue
	if [ "$t" = "$ORIG" ]; then
		eval "exec ${f##*/}<&-" 2>/dev/null
	fi
done
# Delete the download for real - unlike v4, this is unconditional: keeping
# the file is what filled fresh routers, and a failed install can simply
# download it again.
rm -f "$ORIG"
[ "$SELF" != "$ORIG" ] && rm -f "$SELF"
cd "$TMPD" || exit 1
chmod +x install.sh
FORCE="${FORCE:-0}" ./install.sh
RC=$?
exit $RC
__PAYLOAD_BELOW__
