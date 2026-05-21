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
    ;;
  x86_64|amd64)
    LINUX_ARCH="x64"
    ;;
  *)
    echo "Error: Unsupported architecture for the current upstream workaround: $ARCH" >&2
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
PRELOAD_SCRIPT="$NODE_INSTALL_DIR/copilot-preload.js"
NODE_WRAPPER="$NODE_INSTALL_DIR/bin/node-wrapper"
COPILOT_WRAPPER="$INSTALL_PREFIX/bin/copilot"
GLIBC_PREFIX="${GLIBC_PREFIX:-$INSTALL_PREFIX/glibc}"
GLIBC_LD_SO=""
SSL_CERT_FILE="$INSTALL_PREFIX/etc/tls/cert.pem"
SSL_CERT_DIR="$INSTALL_PREFIX/etc/tls/certs"

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

run_linux_node() {
  env -u LD_PRELOAD \
    PATH="$GLIBC_PREFIX/bin:$PATH" \
    SSL_CERT_FILE="$SSL_CERT_FILE" \
    SSL_CERT_DIR="$SSL_CERT_DIR" \
    NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE" \
    HOME="$HOME" \
    PREFIX="$INSTALL_PREFIX" \
    NPM_CONFIG_PREFIX="$INSTALL_PREFIX" \
    npm_config_prefix="$INSTALL_PREFIX" \
    "$GLIBC_LD_SO" "$LINUX_NODE" "$@"
}

run_linux_npm() {
  run_linux_node "$LINUX_NPM_CLI" "$@"
}

find_glibc_loader() {
  if [ -x "$GLIBC_PREFIX/bin/ld.so" ]; then
    GLIBC_LD_SO="$GLIBC_PREFIX/bin/ld.so"
    return 0
  fi

  local candidate
  for candidate in "$GLIBC_PREFIX"/lib/ld-*; do
    if [ -e "$candidate" ]; then
      GLIBC_LD_SO="$candidate"
      return 0
    fi
  done

  return 1
}

write_node_wrapper() {
  mkdir -p "$(dirname "$NODE_WRAPPER")"
  cat > "$NODE_WRAPPER" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
GLIBC_PREFIX="${GLIBC_PREFIX}"
REAL_NODE="\$(dirname "\$0")/node"
LD_SO="${GLIBC_LD_SO}"
export PATH="\$GLIBC_PREFIX/bin:\$PATH"
unset LD_PRELOAD
exec "\$LD_SO" "\$REAL_NODE" "\$@"
EOF
  chmod +x "$NODE_WRAPPER"
}

write_preload_script() {
  cat > "$PRELOAD_SCRIPT" <<EOF
const path = require('path');
const wrapperPath = path.join(__dirname, 'bin', 'node-wrapper');
Object.defineProperty(process, 'execPath', {
  value: wrapperPath,
  writable: true,
  configurable: true,
});
if (
  process.argv[0] &&
  (process.argv[0].includes('/ld.so') || process.argv[0].includes('/ld-linux-'))
) {
  process.argv[0] = wrapperPath;
}
EOF
}

write_copilot_wrapper() {
  mkdir -p "$(dirname "$COPILOT_WRAPPER")"
  cat > "$COPILOT_WRAPPER" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e
INSTALL_PREFIX="${INSTALL_PREFIX}"
GLIBC_PREFIX="\${GLIBC_PREFIX:-${GLIBC_PREFIX}}"
NODE_LINUX_DIR="\${NODE_LINUX_DIR:-${NODE_INSTALL_DIR}}"
LINUX_NODE="\$NODE_LINUX_DIR/bin/node"
PRELOAD="\$NODE_LINUX_DIR/copilot-preload.js"
COPILOT="${INSTALL_ROOT}/npm-loader.js"
LD_SO="\${GLIBC_LD_SO:-${GLIBC_LD_SO}}"
export SSL_CERT_FILE="${SSL_CERT_FILE}"
export SSL_CERT_DIR="${SSL_CERT_DIR}"
export NODE_EXTRA_CA_CERTS="${SSL_CERT_FILE}"
export PATH="\$GLIBC_PREFIX/bin:\$PATH"
unset LD_PRELOAD
exec "\$LD_SO" "\$LINUX_NODE" -r "\$PRELOAD" "\$COPILOT" "\$@"
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

echo "This setup uses Termux glibc-runner plus an official Linux Node.js build."
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

if ! find_glibc_loader; then
  print_error "glibc loader not found under $GLIBC_PREFIX"
  exit 1
fi

print_step "Step 1/5: Downloading Linux Node.js"
download_linux_node
write_node_wrapper
write_preload_script
print_success "Linux Node.js prepared under $NODE_INSTALL_DIR"

print_step "Step 2/5: Installing GitHub Copilot CLI under glibc"

COPILOT_SPEC="@github/copilot"
COPILOT_LINUX_SPEC="@github/copilot-linux-${LINUX_ARCH}"
if [ "$COPILOT_VERSION" != "latest" ]; then
  COPILOT_SPEC="${COPILOT_SPEC}@${COPILOT_VERSION}"
  COPILOT_LINUX_SPEC="${COPILOT_LINUX_SPEC}@${COPILOT_VERSION}"
fi

run_linux_npm install -g "$COPILOT_SPEC" "$COPILOT_LINUX_SPEC"

if [ ! -f "$INSTALL_ROOT/npm-loader.js" ]; then
  print_error "Install root not found at $INSTALL_ROOT after npm install"
  exit 1
fi

print_success "GitHub Copilot CLI installed under $INSTALL_ROOT"

print_step "Step 3/5: Writing Termux launcher"
write_copilot_wrapper
print_success "Installed wrapper at $COPILOT_WRAPPER"

print_step "Step 4/5: Verifying Linux package install"
if [ ! -x "$INSTALL_PREFIX/lib/node_modules/@github/copilot-linux-${LINUX_ARCH}/copilot" ]; then
  print_error "Linux Copilot binary package missing: @github/copilot-linux-${LINUX_ARCH}"
  exit 1
fi
print_success "Linux Copilot binary package detected"

print_step "Step 5/5: Verifying launcher"
"$COPILOT_WRAPPER" --version
print_success "Copilot launcher is ready"

print_header "Installation Complete"

echo "GitHub Copilot CLI is installed for Termux via glibc-runner."
echo ""
echo "Notes:"
echo "  • The wrapper runs Copilot with Linux Node.js so upstream linux-arm64/x64 binaries load correctly."
echo "  • If npm overwrites \$PREFIX/bin/copilot during a future update, rerun this script."
echo ""
echo "Next steps:"
echo "  1. Launch Copilot: copilot"
echo "  2. Sign in: /login"
echo ""
