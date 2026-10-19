#!/bin/sh
# Builds dist/plex-exporter_<version>_<arch>.deb from the repo root.
#
#   packaging/build-deb.sh <version> <arch>      # arch: amd64 | arm64
#
# Needs go and dpkg-deb on PATH. The binary is static (CGO_ENABLED=0), so the
# package has no runtime dependencies beyond systemd and adduser.
set -eu

version="${1:?usage: build-deb.sh <version> <arch>}"
arch="${2:?usage: build-deb.sh <version> <arch>}"
version="${version#v}"

root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="$(mktemp -d)"
trap 'rm -rf "$pkg"' EXIT
chmod 755 "$pkg"

cd "$root"
mkdir -p dist

CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
	go build -trimpath -ldflags="-s -w" -o "$pkg/usr/bin/plex-exporter" .

install -D -m 644 packaging/debian/plex-exporter.service \
	"$pkg/lib/systemd/system/plex-exporter.service"
install -d -m 750 "$pkg/etc/plex-exporter"
install -m 644 packaging/debian/plex-exporter.conf.example \
	"$pkg/etc/plex-exporter/plex-exporter.conf.example"
install -D -m 644 LICENSE "$pkg/usr/share/doc/plex-exporter/copyright"
install -D -m 644 NOTICE "$pkg/usr/share/doc/plex-exporter/NOTICE"
install -D -m 644 THIRD_PARTY_NOTICES.md \
	"$pkg/usr/share/doc/plex-exporter/THIRD_PARTY_NOTICES.md"

install -d "$pkg/DEBIAN"
for script in postinst prerm postrm; do
	install -m 755 "packaging/debian/$script" "$pkg/DEBIAN/$script"
done
echo /etc/plex-exporter/plex-exporter.conf.example >"$pkg/DEBIAN/conffiles"

size="$(du -sk --exclude=DEBIAN "$pkg" | cut -f1)"
cat >"$pkg/DEBIAN/control" <<EOF
Package: plex-exporter
Version: $version
Architecture: $arch
Maintainer: aflat <noreply@github.com>
Installed-Size: $size
Depends: adduser, systemd
Section: net
Priority: optional
Homepage: https://github.com/aflat/plex-exporter
Description: Prometheus exporter for Plex Media Server
 Exposes Plex streams, transcodes, bandwidth and library metrics on :9594
 for Prometheus, run as a systemd service.
EOF

out="dist/plex-exporter_${version}_${arch}.deb"
dpkg-deb --root-owner-group --build "$pkg" "$out" >/dev/null
echo "$out"
