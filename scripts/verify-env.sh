#!/bin/sh
# HarmonyOS Development Environment Verification Script
# Validates all toolchain versions against skill.json

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo "${GREEN}✓${NC} $1"; }
fail() { echo "${RED}✗${NC} $1"; MISSING=1; }
warn() { echo "${YELLOW}⚠${NC} $1"; }

echo "=== HarmonyOS Development Environment Verification ==="
echo ""

# Platform check
echo "--- Platform ---"
if [ -f "/proc/version" ]; then
    KERNEL=$(cat /proc/version | grep -o "HongMeng Kernel [0-9.]*" || echo "Unknown")
    echo "Kernel: $KERNEL"
    pass "HarmonyOS platform detected"
else
    fail "Cannot detect kernel version"
fi

# Toolchain checks
echo ""
echo "--- Toolchains ---"

# Python
PYTHON_PATH="$HOME/.local/bin/python3"
if [ -x "$PYTHON_PATH" ]; then
    VERSION=$($PYTHON_PATH -c "import sys; print(sys.version.split()[0])")
    if [ "$VERSION" = "3.12.8" ]; then
        pass "Python 3.12.8 at $PYTHON_PATH"
    else
        warn "Python $VERSION (expected 3.12.8)"
    fi
    # Check symbol exports
    SYMBOLS=$(nm -D "$PYTHON_PATH" 2>/dev/null | grep -c " T Py" || echo "0")
    if [ "$SYMBOLS" -ge 1500 ]; then
        pass "Python exports $SYMBOLS Py symbols (-rdynamic)"
    else
        warn "Python exports only $SYMBOLS symbols"
    fi
else
    fail "Python not found at $PYTHON_PATH"
fi

# Rust
RUSTC_PATH="$HOME/.rust/bin/rustc"
if [ -x "$RUSTC_PATH" ]; then
    VERSION=$($RUSTC_PATH --version | grep -o "rustc [0-9.]*" | cut -d' ' -f2)
    if [ "$VERSION" = "1.95.0" ]; then
        pass "Rust 1.95.0 at $RUSTC_PATH"
    else
        warn "Rust $VERSION (expected 1.95.0)"
    fi
else
    fail "Rust not found at $RUSTC_PATH"
fi

# Cargo
CARGO_PATH="$HOME/.rust/bin/cargo"
if [ -x "$CARGO_PATH" ]; then
    VERSION=$($CARGO_PATH --version | grep -o "cargo [0-9.]*" | cut -d' ' -f2)
    pass "Cargo $VERSION at $CARGO_PATH"
else
    fail "Cargo not found at $CARGO_PATH"
fi

# Go
GO_PATH="$HOME/Claude/go-build/go/bin/go"
if [ -x "$GO_PATH" ]; then
    VERSION=$($GO_PATH version | grep -o "go[0-9.]*" | head -1)
    if [ "$VERSION" = "go1.22.5" ]; then
        pass "Go 1.22.5 at $GO_PATH"
    else
        warn "Go $VERSION (expected 1.22.5)"
    fi
else
    fail "Go not found at $GO_PATH"
fi

# Node.js
if command -v node &>/dev/null; then
    VERSION=$(node -v | tr -d 'v')
    if [ "$VERSION" = "24.13.0" ]; then
        pass "Node.js 24.13.0"
    else
        warn "Node.js $VERSION (expected 24.13.0)"
    fi
else
    fail "Node.js not found"
fi

# llama.cpp
LLAMA_PATH="$HOME/Claude/llama.cpp/build/bin/llama-cli"
if [ -x "$LLAMA_PATH" ]; then
    pass "llama.cpp at $LLAMA_PATH"
else
    fail "llama.cpp not found at $LLAMA_PATH"
fi

# eza
EZA_PATH="$HOME/Claude/eza-build/eza/target/release/eza"
if [ -x "$EZA_PATH" ]; then
    VERSION=$($EZA_PATH --version | grep -o "v[0-9.]*" | head -1)
    pass "eza $VERSION at $EZA_PATH"
else
    fail "eza not found at $EZA_PATH"
fi

# bat
BAT_PATH="$HOME/Claude/bat-build/bat/target/release/bat"
if [ -x "$BAT_PATH" ]; then
    VERSION=$($BAT_PATH --version | grep -o "bat [0-9.]*" | cut -d' ' -f2)
    pass "bat $VERSION at $BAT_PATH"
else
    fail "bat not found at $BAT_PATH"
fi

# starship
STARSHIP_PATH="$HOME/Claude/starship-build/starship/target/release/starship"
if [ -x "$STARSHIP_PATH" ]; then
    VERSION=$($STARSHIP_PATH --version | grep -o "starship [0-9.]*" | cut -d' ' -f2)
    pass "starship $VERSION at $STARSHIP_PATH"
else
    fail "starship not found at $STARSHIP_PATH"
fi

# mihomo
MIHOMO_PATH="$HOME/Claude/mihomo-build/bin/mihomo-linux-arm64"
if [ -x "$MIHOMO_PATH" ]; then
    pass "mihomo at $MIHOMO_PATH"
else
    fail "mihomo not found at $MIHOMO_PATH"
fi

# Dropbear
DROPBEAR_PATH="$HOME/.local/bin/dropbear"
if [ -x "$DROPBEAR_PATH" ]; then
    VERSION=$($DROPBEAR_PATH -V 2>&1 | grep -o "Dropbear v[0-9.]*" | head -1)
    pass "$VERSION at $DROPBEAR_PATH"
else
    fail "Dropbear not found at $DROPBEAR_PATH"
fi

# OpenSSH
SSH_PATH="$HOME/Claude/openssh-build/openssh-prefix/bin/ssh"
if [ -x "$SSH_PATH" ]; then
    VERSION=$($SSH_PATH -V 2>&1 | grep -o "OpenSSH_[0-9.]*p[0-9]*" | head -1)
    pass "$VERSION at $SSH_PATH"
else
    warn "OpenSSH not found at $SSH_PATH (optional)"
fi

SSHD_PATH="$HOME/Claude/openssh-build/openssh-prefix/bin/sshd"
if [ -x "$SSHD_PATH" ]; then
    pass "sshd at $SSHD_PATH"
fi

SCP_PATH="$HOME/Claude/openssh-build/openssh-prefix/bin/scp"
if [ -x "$SCP_PATH" ]; then
    pass "scp at $SCP_PATH"
fi

SSH_AGENT_PATH="$HOME/Claude/openssh-build/openssh-prefix/bin/ssh-agent"
if [ -x "$SSH_AGENT_PATH" ]; then
    pass "ssh-agent at $SSH_AGENT_PATH"
fi

PASSWD_COMPAT="$HOME/Claude/openssh-build/passwd_compat/passwd_compat_signed.so"
if [ -f "$PASSWD_COMPAT" ]; then
    pass "passwd_compat.so at $PASSWD_COMPAT"
else
    warn "passwd_compat.so not found (required for OpenSSH sshd)"
fi

# PyTorch (optional)
echo ""
echo "--- Optional Tools ---"
PYTHON=$HOME/.local/bin/python3
if [ -x "$PYTHON" ]; then
    TORCH_VERSION=$($PYTHON -c "import torch; print(torch.__version__)" 2>/dev/null || echo "not installed")
    if [ "$TORCH_VERSION" = "2.5.0a0+gita8d6fb" ]; then
        pass "PyTorch v2.5.1 ($TORCH_VERSION)"
        # Check LAPACK support
        LAPACK=$($PYTHON -c "import torch; m=torch.randn(3,3); torch.det(m); print('OK')" 2>/dev/null || echo "FAIL")
        if [ "$LAPACK" = "OK" ]; then
            pass "PyTorch LAPACK enabled (torch.det() works)"
        else
            warn "PyTorch LAPACK not working (torch.det() fails)"
        fi
        # Check NumPy support
        NUMPY=$($PYTHON -c "import numpy,torch; torch.from_numpy(numpy.array([1.0])); print('OK')" 2>/dev/null || echo "FAIL")
        if [ "$NUMPY" = "OK" ]; then
            pass "PyTorch NumPy support (torch.from_numpy() works)"
        else
            warn "PyTorch NumPy not working"
        fi
    elif [ "$TORCH_VERSION" = "not installed" ]; then
        warn "PyTorch not installed"
    else
        warn "PyTorch $TORCH_VERSION (expected 2.5.0a0+gita8d6fb)"
    fi
fi

# Environment checks
echo ""
echo "--- Environment ---"

# TMPDIR
if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    pass "TMPDIR=$TMPDIR"
else
    fail "TMPDIR not set or not a directory (should be $HOME/Claude/tmpdir)"
fi

# LD_LIBRARY_PATH
if echo "$LD_LIBRARY_PATH" | grep -q "^/usr/lib:"; then
    pass "LD_LIBRARY_PATH starts with /usr/lib (correct order)"
else
    fail "LD_LIBRARY_PATH should start with /usr/lib"
fi

# CC/CXX
if [ "$CC" = "/data/service/hnp/bin/clang" ]; then
    pass "CC=$CC"
else
    warn "CC not set to clang (current: ${CC:-not set})"
fi

# Code signing tool
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
if [ -x "$SIGN_TOOL" ]; then
    pass "binary-sign-tool available"
else
    fail "binary-sign-tool not found"
fi

# Linker wrapper
LINKER_WRAPPER="$HOME/Claude/lib/linker_wrapper/ld.lld"
if [ -x "$LINKER_WRAPPER" ]; then
    pass "ld.bfd wrapper at $LINKER_WRAPPER"
else
    warn "Linker wrapper not created (may need for clang linking)"
fi

# LD_PRELOAD (for OpenSSH)
if [ -n "$LD_PRELOAD" ]; then
    pass "LD_PRELOAD=$LD_PRELOAD"
else
    warn "LD_PRELOAD not set (required for OpenSSH sshd)"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ -n "$MISSING" ]; then
    echo "${RED}Some checks failed. Run install scripts for missing tools.${NC}"
    exit 1
else
    echo "${GREEN}All critical tools verified.${NC}"
    exit 0
fi