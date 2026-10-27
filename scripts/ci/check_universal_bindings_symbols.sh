#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0 OR ISC
set -euo pipefail
# `comm` needs both lists sorted the same way; underscores collate differently
# outside the C locale.
export LC_ALL=C

# Checks the libcrypto an `AWS_LC_SYS_UNIVERSAL_ONLY` cc-builder build produces:
# it leaves out `OUTSIDE_UNIVERSAL_BINDINGS` (builder/cc_builder.rs) and still
# defines every function the universal bindings declare.

REPO_ROOT=$(git rev-parse --show-toplevel)
UNIVERSAL="${REPO_ROOT}/aws-lc-sys/src/universal_crypto.rs"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "${BUILD_DIR}"' EXIT

AWS_LC_SYS_UNIVERSAL_ONLY=1 CARGO_TARGET_DIR="${BUILD_DIR}" cargo build -p aws-lc-sys --no-default-features --manifest-path "${REPO_ROOT}/Cargo.toml"
LIBCRYPTO=$(find "${BUILD_DIR}" -type f -name 'libaws_lc_*_crypto.a' -print -quit)
test -f "${LIBCRYPTO}" || { echo "FAIL: libcrypto archive not found in ${BUILD_DIR}"; exit 1; }
grep -q 'link_name = "' "${UNIVERSAL}" || { echo "FAIL: no link_name attributes in ${UNIVERSAL}"; exit 1; }

# rust_wrapper.h declares these, but no AWS-LC source defines them; aws-lc-sys
# implements ERR_GET_LIB, ERR_GET_REASON and ERR_GET_FUNC in Rust instead. The
# bindings also declare BORINGSSL_integrity_test without a prefixed link name;
# only FIPS builds define it.
NEVER_DEFINED='_ERR_GET_(LIB|REASON|FUNC)_RUST$'

grep -o 'link_name = "[^"]*"' "${UNIVERSAL}" |
  cut -d '"' -f 2 |
  grep -Ev "${NEVER_DEFINED}" |
  sort -u >"${BUILD_DIR}/declared.txt"
nm -g --defined-only "${LIBCRYPTO}" |
  awk 'NF == 3 { sub(/^_/, "", $3); print $3 }' |
  sort -u >"${BUILD_DIR}/defined.txt"

if grep -q '_X509_verify_cert$' "${BUILD_DIR}/defined.txt"; then
  echo "FAIL: ${LIBCRYPTO} defines X509_verify_cert, so the build kept the sources outside the universal bindings"
  exit 1
fi
MISSING=$(comm -23 "${BUILD_DIR}/declared.txt" "${BUILD_DIR}/defined.txt")
if [[ -n "${MISSING}" ]]; then
  echo "FAIL: declared by the universal bindings but not defined in ${LIBCRYPTO}:"
  echo "${MISSING}"
  exit 1
fi
echo "All $(($(wc -l <"${BUILD_DIR}/declared.txt"))) functions the universal bindings declare are defined."
