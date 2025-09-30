# Seed Arch keyring from a local file (no network in Docker)

## tldr;

— on the official Pacman Mirrorlist Generator there’s a checkbox for this.

How to only use mirrors that work:

Open the generator.

Pick your nearby countries (e.g., Germany, Netherlands).

Select https (recommended).

Tick “Use mirror status” — this uses Arch’s live Mirror Status data and only lists up-to-date mirrors. 
archlinux.org

If you want to automate/refresh this regularly, use reflector instead of the web form, e.g.:

```bash
sudo pacman -S reflector
sudo reflector --country Germany,Netherlands \
  --protocol https --ipv4 --ipv6 \
  --latest 20 --sort rate \
  --save /etc/pacman.d/mirrorlist
```

Reflector pulls from the Mirror Status feed, filters to fresh mirrors, sorts by speed/age, and writes your mirrorlist. 
ArchWiki


We install `archlinux-keyring` from a **locally downloaded** package so the
Docker build doesn’t need outbound TLS (or proxy tweaks) just to trust mirrors.

## 1) Download the package on your workstation

You can use a web browser or `curl` on your host.

### Option A — Browser (recommended)
1. Open a mirror index (example for x86_64):
   ```
   https://geo.mirror.pkgbuild.com/core/os/x86_64/
   ```
2. Download the latest file named like:
   ```
   archlinux-keyring-<VERSION>-any.pkg.tar.zst
   ```
3. (Optional) Rename it to a stable name so the Dockerfile doesn’t change:
   ```bash
   mv archlinux-keyring-*.pkg.tar.zst archlinux-keyring.pkg.tar.zst
   ```

### Option B — Host `curl`
Pick a mirror and pull the latest automatically (adjust proxy flags if needed):

```bash
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
```

> Tip: Verify it’s a valid zstd tarball:
> ```bash
> file archlinux-keyring.pkg.tar.zst
> # → Zstandard compressed data
> ```

## 2) Put the file next to your Dockerfile

Your tree should include:
```
Dockerfile
seed-arch-keyring-local-file.sh
archlinux-keyring.pkg.tar.zst
```

## 3) Use the local installer in the Dockerfile

```dockerfile
# Copy the local package + the tiny installer
COPY archlinux-keyring.pkg.tar.zst /opt/archlinux-keyring.pkg.tar.zst
COPY seed-arch-keyring-local-file.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/seed-arch-keyring-local-file.sh

# Install keyring from the local file (no network)
RUN /usr/local/bin/seed-arch-keyring-local-file.sh --pkg /opt/archlinux-keyring.pkg.tar.zst
```

### (Optional) Immediately update behind a proxy
If you also want to run `pacman -Sy` / `-Syyu` during build and your environment
needs a proxy/CA, create `proxy.env` with values like:

```bash
# proxy.env
MY_PROXY_URL=http://proxy:3128
MY_NO_PROXY_STR=127.0.0.1,localhost
# Base64-encoded PEM if your proxy intercepts TLS (optional)
# MY_CERT_BASE64_STR=LS0tLS1CRUdJTiBDRVJUSUZJQ0...
MY_DISABLE_IPV6_BOOL=true
```

Then:

```dockerfile
COPY proxy.env /usr/local/bin/proxy.env
RUN /usr/local/bin/seed-arch-keyring-local-file.sh \
      --pkg /opt/archlinux-keyring.pkg.tar.zst \
      --also-update \
      --load-env-file /usr/local/bin/proxy.env
```
