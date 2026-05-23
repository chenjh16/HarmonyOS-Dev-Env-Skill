# HarmonyOS third-party toolchain PATH configuration
# This file is loaded by zsh on every session (.zshenv is always sourced)

# Local compiled Python (with -rdynamic, can load user-dir .so extensions)
# This Python exports 948+ Py symbols (1521 total), enabling extension module loading
export LOCAL_PYTHON_HOME="$HOME/.local"
export PATH="$LOCAL_PYTHON_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$LOCAL_PYTHON_HOME/lib:$LD_LIBRARY_PATH"

# Rust (aarch64-unknown-linux-ohos + musl cargo)
# NOTE: /usr/lib must come before $RUST_HOME/lib because:
# - Rust lib has OpenSSL with OPENSSLOH_3.0.0 symbols (OpenHarmony ABI)
# - /usr/lib has OpenSSL with OPENSSL_3.0.0 symbols (standard ABI)
# - musl-linked binaries (ssh, ssh-keygen) need standard OpenSSL symbols
export RUST_HOME="$HOME/.rust"
export PATH="$RUST_HOME/bin:$PATH"
export LD_LIBRARY_PATH="/usr/lib:$RUST_HOME/lib:/system/lib64:$LD_LIBRARY_PATH"
export CARGO_HOME="$RUST_HOME"
export RUSTUP_HOME="$RUST_HOME"

# llama.cpp
export LLAMA_HOME="$HOME/Claude/llama.cpp/build/bin"
export PATH="$LLAMA_HOME:$PATH"
export LD_LIBRARY_PATH="$LLAMA_HOME:$LD_LIBRARY_PATH"

# eza (modern ls replacement, compiled from Rust)
export EZA_HOME="$HOME/Claude/eza-build/eza/target/release"
export PATH="$EZA_HOME:$PATH"

# bat (cat clone with wings, compiled from Rust)
export BAT_HOME="$HOME/Claude/bat-build/bat/target/release"
export PATH="$BAT_HOME:$PATH"

# starship (cross-shell prompt, compiled from Rust)
export STARSHIP_HOME="$HOME/Claude/starship-build/starship/target/release"
export PATH="$STARSHIP_HOME:$PATH"
export STARSHIP_CONFIG="/data/storage/el2/base/haps/entry/files/starship/starship.toml"

# Go
export GO_HOME="$HOME/Claude/go-build/go"
export PATH="$GO_HOME/bin:$PATH"
export GOPATH="$HOME/Claude/go-build/gopath"
export GOMODCACHE="$HOME/Claude/go-build/gomodcache"
export GOPROXY="https://goproxy.cn,direct"

# SSL certificate for cargo (crates.io access)
export SSL_CERT_FILE="$RUST_HOME/cacert.pem"

# TMPDIR (override /tmp which is read-only on HarmonyOS)
export TMPDIR="$HOME/Claude/tmpdir"

# PyTorch library path (if installed)
if [ -d "$HOME/.local/lib/python3.12/site-packages/torch/lib" ]; then
    export LD_LIBRARY_PATH="$HOME/.local/lib/python3.12/site-packages/torch/lib:$LD_LIBRARY_PATH"
fi