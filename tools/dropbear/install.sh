#!/usr/bin/sh
# install.sh - Install Dropbear SSH server on HarmonyOS
# Usage: ./install.sh [--skip-build]
#
# This script downloads, builds, and installs Dropbear SSH server for HarmonyOS.
# Note: Password authentication is disabled due to missing crypt() function.

set -e

DROPBEAR_VERSION="2024.86"
BUILD_DIR="$HOME/Claude/dropbear-build"
INSTALL_DIR="$HOME/.local"
SYSROOT="/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
OBJCOPY="/data/service/hnp/bin/llvm-objcopy"

# Check for ld.bfd wrapper
LINKER_WRAPPER="$HOME/Claude/lib/linker_wrapper/ld.lld"
if [ ! -f "$LINKER_WRAPPER" ]; then
    echo "Creating ld.bfd wrapper..."
    mkdir -p "$HOME/Claude/lib/linker_wrapper"
    cat > "$LINKER_WRAPPER" << 'EOF'
#!/bin/sh
exec /data/service/hnp/bin/ld.bfd "$@"
EOF
    chmod +x "$LINKER_WRAPPER"
fi

# Download source if not already present
if [ ! -d "$BUILD_DIR/dropbear-$DROPBEAR_VERSION" ]; then
    echo "Downloading Dropbear $DROPBEAR_VERSION..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    curl -L --connect-timeout 30 -o "dropbear-$DROPBEAR_VERSION.tar.bz2" \
        "https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR_VERSION.tar.bz2"
    tar xjf "dropbear-$DROPBEAR_VERSION.tar.bz2"
fi

cd "$BUILD_DIR/dropbear-$DROPBEAR_VERSION"

# Create config.h
echo "Creating config.h..."
cat > config.h << 'CONFIG_EOF'
#ifndef DROPBEAR_CONFIG_H
#define DROPBEAR_CONFIG_H

#undef HAVE_GETRANDOM
#define HAVE_CLOCK_GETTIME 1
#define HAVE_DAEMON 1
#define HAVE_GETADDRINFO 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_WRITEV 1
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_STRUCT_IN6_ADDR 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_STRUCT_ADDRINFO 1
#define HAVE_IPV6 1

#endif
CONFIG_EOF

# Create options.h based on default_options.h
echo "Creating options.h..."
cat > src/options.h << 'OPTIONS_EOF'
#ifndef DROPBEAR_OPTIONS_H
#define DROPBEAR_OPTIONS_H

#include "config.h"

#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_CLI_PASSWORD_AUTH 0
#define RSA_PRIV_FILENAME "~/.local/etc/dropbear/dropbear_rsa_host_key"
#define ECDSA_PRIV_FILENAME "~/.local/etc/dropbear/dropbear_ecdsa_host_key"
#define ED25519_PRIV_FILENAME "~/.local/etc/dropbear/dropbear_ed25519_host_key"
#define DROPBEAR_PIDFILE "~/.local/var/run/dropbear.pid"

#include "default_options.h"
#include "sysoptions.h"

#endif
OPTIONS_EOF

# Build libtommath
echo "Building libtommath..."
cd libtommath
if [ ! -f libtommath.a ]; then
    make -f Makefile.in \
        CC=/data/service/hnp/bin/clang \
        AR=/data/service/hnp/bin/ar \
        RANLIB=/data/service/hnp/bin/ranlib \
        CFLAGS="-O2 -I. -I../src -I../libtomcrypt/src/headers -I.. -Wno-deprecated" \
        IGNORE_SPEED=1
fi
cd ..

# Build libtomcrypt
echo "Building libtomcrypt..."
cd libtomcrypt
if [ ! -f libtomcrypt.a ]; then
    make -f makefile.unix \
        CC=/data/service/hnp/bin/clang \
        AR=/data/service/hnp/bin/ar \
        RANLIB=/data/service/hnp/bin/ranlib \
        CFLAGS="-O2 -Isrc/headers -I../libtommath -I.. -I../src -DLTC_SOURCE -DUSE_LTM -DLTM_DESC -DDROPBEAR_BUNDLED_LIBTOM --sysroot=$SYSROOT" \
        EXTRALIBS="../libtommath/libtommath.a"
fi
cd ..

# Build dropbear
echo "Building dropbear..."
mkdir -p obj

CC=/data/service/hnp/bin/clang
CFLAGS="-B$HOME/Claude/lib/linker_wrapper -O2 -Wall -DDROPBEAR_SERVER=1 -DDROPBEAR_CLIENT=1"
CPPFLAGS="-I. -Isrc -Ilibtomcrypt/src/headers -Ilibtommath --sysroot=$SYSROOT"
LDFLAGS="-B$HOME/Claude/lib/linker_wrapper --sysroot=$SYSROOT -L$SYSROOT/usr/lib/aarch64-linux-ohos"

# Compile common objects
for src in src/*.c; do
    obj="obj/$(basename ${src%.c}.o)"
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
        $CC $CPPFLAGS $CFLAGS -c "$src" -o "$obj"
    fi
done

# Link binaries
echo "Linking dropbear..."
COMMON_OBJS=$(ls obj/*.o | grep -v 'svr-\|cli-\|dropbearkey\|dropbearconvert')
SVR_OBJS=$(ls obj/svr-*.o)
CLI_OBJS=$(ls obj/cli-*.o)

$CC $LDFLAGS -o dropbear $COMMON_OBJS $SVR_OBJS libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lz
$CC $LDFLAGS -o dbclient $COMMON_OBJS $CLI_OBJS libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lz
$CC $LDFLAGS -o dropbearkey $COMMON_OBJS obj/dropbearkey.o libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lz
$CC $LDFLAGS -o dropbearconvert $COMMON_OBJS obj/dropbearconvert.o obj/keyimport.o obj/signkey_ossh.o libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lz

# Sign binaries
echo "Signing binaries..."
for binary in dropbear dbclient dropbearkey dropbearconvert; do
    $OBJCOPY --remove-section=.codesign "$binary" "${binary}.unsigned" 2>/dev/null || cp "$binary" "${binary}.unsigned"
    $SIGN_TOOL sign -selfSign 1 -inFile "${binary}.unsigned" -outFile "${binary}.signed" -signAlg SHA256withECDSA
    mv "${binary}.signed" "$binary"
    rm "${binary}.unsigned"
    chmod +x "$binary"
done

# Install
echo "Installing to $INSTALL_DIR/bin..."
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/etc/dropbear"
mkdir -p "$INSTALL_DIR/var/run"

cp dropbear dbclient dropbearkey dropbearconvert "$INSTALL_DIR/bin/"

# Generate host keys if not exist
echo "Generating host keys..."
if [ ! -f "$INSTALL_DIR/etc/dropbear/dropbear_rsa_host_key" ]; then
    "$INSTALL_DIR/bin/dropbearkey" -t rsa -f "$INSTALL_DIR/etc/dropbear/dropbear_rsa_host_key" -s 2048
fi
if [ ! -f "$INSTALL_DIR/etc/dropbear/dropbear_ecdsa_host_key" ]; then
    "$INSTALL_DIR/bin/dropbearkey" -t ecdsa -f "$INSTALL_DIR/etc/dropbear/dropbear_ecdsa_host_key" -s 256
fi
if [ ! -f "$INSTALL_DIR/etc/dropbear/dropbear_ed25519_host_key" ]; then
    "$INSTALL_DIR/bin/dropbearkey" -t ed25519 -f "$INSTALL_DIR/etc/dropbear/dropbear_ed25519_host_key"
fi

echo ""
echo "=== Installation Complete ==="
echo "Binaries installed to: $INSTALL_DIR/bin/"
echo "Host keys in: $INSTALL_DIR/etc/dropbear/"
echo ""
echo "To start SSH server (IMPORTANT: use -e flag for env passthrough):"
echo "  $INSTALL_DIR/bin/dropbear -p 2222 -e"
echo ""
echo "To connect (any non-system username works):"
echo "  ssh -p 2222 chenh@localhost"
echo "  ssh -p 2222 user@localhost"
echo "  ssh -p 2222 currentUser@localhost"
echo "  $INSTALL_DIR/bin/dbclient 20020106@localhost"
echo ""
echo "Note: Password authentication is disabled (no crypt() function)"
echo "      Only pubkey authentication is supported."
echo "      Use -e flag when starting dropbear to pass env vars to child sessions."
echo "      Interactive sessions (PTY) have limited job control (TIOCSCTTY fails)."