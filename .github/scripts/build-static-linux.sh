#!/bin/sh
# Build a fully static aria2c (musl + OpenSSL) inside an Alpine container.
#   docker run --rm -v "$PWD":/src -w /src alpine:3.22 sh .github/scripts/build-static-linux.sh
# Result: ./dist/aria2c
set -eu

apk add --no-cache \
  build-base autoconf automake libtool gettext-dev pkgconf git perl linux-headers \
  zlib-dev zlib-static \
  expat-dev expat-static sqlite-dev sqlite-static \
  c-ares-dev libssh2-dev libssh2-static

# Alpine's static OpenSSL keeps the legacy provider (RC4, which aria2 loads at
# startup for BitTorrent) in a loadable module, which a static binary cannot
# open. Build OpenSSL with that provider compiled in.
OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
(
  cd /tmp
  wget -q "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
  echo "$OPENSSL_SHA256  openssl-$OPENSSL_VERSION.tar.gz" | sha256sum -c -
  tar xzf "openssl-$OPENSSL_VERSION.tar.gz"
  cd "openssl-$OPENSSL_VERSION"
  # openssldir=/etc/ssl: where most distributions keep their CA certificates
  ./Configure no-shared no-module no-tests --prefix=/opt/openssl --libdir=lib --openssldir=/etc/ssl
  make -j"$(nproc)" build_sw
  make install_sw
)
export PKG_CONFIG_PATH=/opt/openssl/lib/pkgconfig

autoreconf -i
./configure ARIA2_STATIC=yes \
  --without-gnutls --with-openssl \
  --without-libxml2 --with-libexpat \
  --disable-nls --disable-dependency-tracking
make -j"$(nproc)"

mkdir -p dist
cp src/aria2c dist/aria2c
strip dist/aria2c
# fail the build if the binary still needs a shared library
if ldd dist/aria2c 2>&1 | grep -q '=>'; then
  ldd dist/aria2c
  echo "aria2c is not fully static" >&2
  exit 1
fi
dist/aria2c --version
