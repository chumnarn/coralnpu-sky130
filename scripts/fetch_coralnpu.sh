#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Clone google-coral/coralnpu into third_party/coralnpu at a known-good commit.
#   CORALNPU_REV=main ./scripts/fetch_coralnpu.sh     # to try the latest
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${CORALNPU_DIR:-${ROOT}/third_party/coralnpu}"
# Commit this project was prepared against (2026-10-29)
REV="${CORALNPU_REV:-11619e284fcfb373c11a89f1e6fc0be6eea6cce2}"

if [[ -d "${DEST}" && ! -d "${DEST}/.git" ]]; then
  # e.g. left behind by an earlier 'make sw' before the repo was fetched
  echo ">>> ${DEST} exists but is not a git checkout - moving it aside"
  mv "${DEST}" "${DEST}.bak.$(date +%s)"
fi
if [[ ! -d "${DEST}/.git" ]]; then
  mkdir -p "$(dirname "${DEST}")"
  git clone https://github.com/google-coral/coralnpu "${DEST}"
fi
cd "${DEST}"
git fetch --quiet origin
git checkout --quiet "${REV}"
echo ">>> CoralNPU at $(git rev-parse --short HEAD) in ${DEST}"
echo ">>> Bazel version required: $(cat .bazelversion 2>/dev/null || echo '?')"
