MIRROR="https://geo.mirror.pkgbuild.com/core/os/x86_64/"

# If you need a proxy on your HOST, uncomment and set these:
# PROXY_URL="http://proxy:3128"
# CACERT="/path/to/corporate-ca.pem"

curl ${PROXY_URL:+--proxy "$PROXY_URL"} ${CACERT:+--cacert "$CACERT"} -fsSL "$MIRROR" \
| grep -oE 'archlinux-keyring-[^"]+\.pkg\.tar\.zst' \
| sort -V | tail -1 | while read -r PKG; do
  curl ${PROXY_URL:+--proxy "$PROXY_URL"} ${CACERT:+--cacert "$CACERT"} -fLO "$MIRROR$PKG"
done

# Give it a stable name for Docker
mv archlinux-keyring-*.pkg.tar.zst archlinux-keyring.pkg.tar.zst
file archlinux-keyring.pkg.tar.zst
