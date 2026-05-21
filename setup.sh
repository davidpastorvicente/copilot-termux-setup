#!/bin/bash

set -euo pipefail

if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "Error: This setup script must be run inside Termux (TERMUX_VERSION not set)." >&2
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64)
    LINUX_ARCH="arm64"
    GLIBC_LD_SO="ld-linux-aarch64.so.1"
    QEMU_CMD="qemu-aarch64"
    QEMU_PKG="qemu-user-aarch64"
    ;;
  x86_64|amd64)
    LINUX_ARCH="x64"
    GLIBC_LD_SO="ld-linux-x86-64.so.2"
    QEMU_CMD="qemu-x86_64"
    QEMU_PKG="qemu-user-x86-64"
    ;;
  *)
    echo "Error: Unsupported architecture for this installer: $ARCH" >&2
    echo "Supported Termux architectures: aarch64/arm64, x86_64/amd64" >&2
    exit 1
    ;;
esac

INSTALL_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_ROOT="$INSTALL_PREFIX/lib/node_modules/@github/copilot"
COPILOT_VERSION="${COPILOT_VERSION:-latest}"
LINUX_NODE_VERSION="${LINUX_NODE_VERSION:-v24.14.1}"
NODE_BASE_DIR="${LINUX_NODE_BASE_DIR:-$HOME/node-linux}"
NODE_INSTALL_DIR="$NODE_BASE_DIR/$LINUX_NODE_VERSION"
LINUX_NODE="$NODE_INSTALL_DIR/bin/node"
LINUX_NPM_CLI="$NODE_INSTALL_DIR/lib/node_modules/npm/bin/npm-cli.js"
QEMU_SYSROOT="$NODE_INSTALL_DIR/qemu-sysroot"
COPILOT_WRAPPER="$INSTALL_PREFIX/bin/copilot"
GLIBC_PREFIX="${GLIBC_PREFIX:-$INSTALL_PREFIX/glibc}"
SSL_CERT_FILE="$INSTALL_PREFIX/etc/tls/cert.pem"
SSL_CERT_DIR="$INSTALL_PREFIX/etc/tls/certs"
QEMU_BIN=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

print_step() {
  echo ""
  echo -e "${GREEN}▶${NC} ${BLUE}$1${NC}"
  echo ""
}

ensure_pkg() {
  local pkgname="$1"
  local check_cmd="${2:-}"

  if [ -n "$check_cmd" ] && command -v "$check_cmd" >/dev/null 2>&1; then
    print_info "$pkgname already available at $(command -v "$check_cmd")"
    return 0
  fi

  if pkg list-installed "$pkgname" >/dev/null 2>&1; then
    print_info "$pkgname already installed"
    return 0
  fi

  print_info "Installing $pkgname"
  pkg install -y "$pkgname"
}

resolve_qemu() {
  QEMU_BIN="$(command -v "$QEMU_CMD" || true)"
  if [ -z "$QEMU_BIN" ]; then
    print_error "$QEMU_CMD not found after installing $QEMU_PKG"
    exit 1
  fi
}

prepare_qemu_sysroot() {
  mkdir -p "$QEMU_SYSROOT/lib"

  local lib
  for lib in \
    "$GLIBC_LD_SO" \
    libc.so.6 \
    libm.so.6 \
    libdl.so.2 \
    libpthread.so.0 \
    libgcc_s.so.1 \
    libstdc++.so.6
  do
    cp -Lf "$GLIBC_PREFIX/lib/$lib" "$QEMU_SYSROOT/lib/$lib"
  done

  ln -sf libc.so.6 "$QEMU_SYSROOT/lib/libc.so"
}

run_linux_node() {
  env -u LD_PRELOAD \
    SSL_CERT_FILE="$SSL_CERT_FILE" \
    SSL_CERT_DIR="$SSL_CERT_DIR" \
    NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE" \
    HOME="$HOME" \
    PREFIX="$INSTALL_PREFIX" \
    NPM_CONFIG_PREFIX="$INSTALL_PREFIX" \
    npm_config_prefix="$INSTALL_PREFIX" \
    "$QEMU_BIN" -L "$QEMU_SYSROOT" "$LINUX_NODE" "$@"
}

run_linux_npm() {
  run_linux_node "$LINUX_NPM_CLI" "$@"
}

write_copilot_wrapper() {
  mkdir -p "$(dirname "$COPILOT_WRAPPER")"
  cat > "$COPILOT_WRAPPER" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e
NODE_DIR="${NODE_INSTALL_DIR}"
SYSROOT="\$NODE_DIR/qemu-sysroot"
REAL_NODE="\$NODE_DIR/bin/node"
ENTRY="${INSTALL_ROOT}/index.js"
exec env -u LD_PRELOAD \\
  COPILOT_RUN_APP=1 \\
  NODE_OPTIONS="\${NODE_OPTIONS:+\$NODE_OPTIONS }--no-warnings" \\
  SSL_CERT_FILE="${SSL_CERT_FILE}" \\
  SSL_CERT_DIR="${SSL_CERT_DIR}" \\
  NODE_EXTRA_CA_CERTS="${SSL_CERT_FILE}" \\
  HOME="${HOME}" \\
  PREFIX="${INSTALL_PREFIX}" \\
  "${QEMU_BIN}" -L "\$SYSROOT" "\$REAL_NODE" "\$ENTRY" "\$@"
EOF
  chmod +x "$COPILOT_WRAPPER"
}

download_linux_node() {
  if [ -x "$LINUX_NODE" ]; then
    print_info "Linux Node.js already present at $LINUX_NODE"
    return 0
  fi

  local node_url="https://nodejs.org/dist/${LINUX_NODE_VERSION}/node-${LINUX_NODE_VERSION}-linux-${LINUX_ARCH}.tar.xz"
  local tmpdir
  tmpdir="$(mktemp -d)"

  print_info "Downloading $node_url"
  curl -fsSL "$node_url" -o "$tmpdir/node.tar.xz"
  mkdir -p "$NODE_BASE_DIR"
  tar -xJf "$tmpdir/node.tar.xz" -C "$tmpdir"
  rm -rf "$NODE_INSTALL_DIR"
  mv "$tmpdir/node-${LINUX_NODE_VERSION}-linux-${LINUX_ARCH}" "$NODE_INSTALL_DIR"
  rm -rf "$tmpdir"
}

print_header "GitHub Copilot CLI on Termux"

echo "This setup uses Linux Node.js under QEMU with a minimal glibc sysroot."
echo ""
echo "  • Termux arch:   $ARCH"
echo "  • Linux arch:    $LINUX_ARCH"
echo "  • Copilot ver.:  $COPILOT_VERSION"
echo "  • Linux Node.js: $LINUX_NODE_VERSION"
echo ""

if [ -t 0 ]; then
  read -r -p "Press Enter to continue or Ctrl+C to abort..."
fi

print_header "Installing dependencies"

print_info "Running pkg update"
pkg update -y || print_warning "pkg update failed, continuing anyway"

ensure_pkg curl curl
ensure_pkg xz-utils xz
ensure_pkg ca-certificates
ensure_pkg glibc-repo

print_info "Refreshing package metadata after enabling glibc repo"
pkg update -y || print_warning "pkg update after glibc-repo failed, continuing anyway"

ensure_pkg glibc-runner
ensure_pkg "$QEMU_PKG" "$QEMU_CMD"
resolve_qemu

if [ ! -r "$GLIBC_PREFIX/lib/$GLIBC_LD_SO" ]; then
  print_error "glibc loader not found at $GLIBC_PREFIX/lib/$GLIBC_LD_SO"
  exit 1
fi

print_step "Step 1/5: Downloading Linux Node.js"
download_linux_node
prepare_qemu_sysroot
print_success "Linux Node.js prepared under $NODE_INSTALL_DIR"

print_step "Step 2/5: Verifying Linux Node.js under QEMU"
run_linux_node --version
print_success "Linux Node.js runs under QEMU"

print_step "Step 3/5: Installing GitHub Copilot CLI"
COPILOT_SPEC="@github/copilot"
if [ "$COPILOT_VERSION" != "latest" ]; then
  COPILOT_SPEC="${COPILOT_SPEC}@${COPILOT_VERSION}"
fi

NPM_CONFIG_OPTIONAL=false npm_config_optional=false run_linux_npm install -g "$COPILOT_SPEC"

if [ ! -f "$INSTALL_ROOT/index.js" ]; then
  print_error "Install root not found at $INSTALL_ROOT after npm install"
  exit 1
fi
print_success "GitHub Copilot CLI installed under $INSTALL_ROOT"

print_step "Step 4/5: Writing Termux launcher"
write_copilot_wrapper
print_success "Installed wrapper at $COPILOT_WRAPPER"

print_step "Step 5/5: Verifying launcher"
"$COPILOT_WRAPPER" --version
print_success "Copilot launcher is ready"

print_header "Installation Complete"

echo "GitHub Copilot CLI is installed for Termux."
echo ""
echo "Notes:"
echo "  • The wrapper runs upstream Copilot with Linux Node.js under QEMU."
echo "  • QEMU uses a minimal glibc sysroot copied from Termux's glibc packages."
echo "  • If npm overwrites \$PREFIX/bin/copilot during a future update, rerun this script."
echo ""
echo "Next steps:"
echo "  1. Launch Copilot: copilot"
echo "  2. Sign in: /login"
echo ""
