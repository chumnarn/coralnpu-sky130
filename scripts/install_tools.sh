#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
# install_tools.sh - one-time tool setup on Ubuntu 22.04 / 24.04 (x86_64)
#
#   1. apt packages   : git, build tools, Icarus Verilog, GTKWave, Python
#   2. Bazelisk       : runs the Bazel version pinned by CoralNPU (.bazelversion)
#   3. Nix + LibreLane: LibreLane 3.0.17 (or 3.1.x) with Yosys/OpenROAD/Magic/KLayout/Netgen
#                       from the FOSSi binary cache
#
# Docker alternative to step 3:  pip3 install git+https://github.com/librelane/librelane@3.0.17
#                                and use LIBRELANE="librelane --dockerized"
# -----------------------------------------------------------------------------
set -euo pipefail
LIBRELANE_REV="${LIBRELANE_REV:-3.0.17}"   # 3.1.0.dev4 also supported (not in the binary cache yet)
LIBRELANE_DIR="${LIBRELANE_DIR:-$HOME/librelane}"

step() { echo; echo "=== $* ==="; }

step "1/3 apt packages"
sudo apt-get update
sudo apt-get install -y git curl build-essential clang python3 python3-pip python3-venv \
  iverilog gtkwave verilator default-jre-headless

step "2/3 Bazelisk (as 'bazel')"
if ! command -v bazel >/dev/null 2>&1; then
  sudo curl -fsSL -o /usr/local/bin/bazel \
    https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
  sudo chmod +x /usr/local/bin/bazel
fi
bazel --version || true

step "3/3 Nix + LibreLane ${LIBRELANE_REV}"
if ! command -v nix >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -fsSL https://artifacts.nixos.org/nix-installer | \
    sh -s -- install --no-confirm --extra-conf "
    extra-substituters = https://nix-cache.fossi-foundation.org
    extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
    extra-experimental-features = nix-command flakes
"
  echo ">>> Nix installed - open a NEW terminal before continuing."
fi
if [[ ! -d "${LIBRELANE_DIR}" ]]; then
  git clone https://github.com/librelane/librelane "${LIBRELANE_DIR}"
fi
git -C "${LIBRELANE_DIR}" fetch --tags --quiet
git -C "${LIBRELANE_DIR}" checkout --quiet "${LIBRELANE_REV}"

cat <<EOF

Done.  Next steps:
  nix-shell ${LIBRELANE_DIR}/shell.nix        # enter the LibreLane environment
  librelane --smoke-test                       # downloads sky130 via ciel + quick test
  cd <coralnpu-sky130> && make help
EOF
