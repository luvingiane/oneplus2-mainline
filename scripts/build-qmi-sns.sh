#!/usr/bin/env bash
# Static aarch64 build of tools/qmi-sns/qmi-sns.c  ->  build/qmi-sns
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH
aarch64-none-linux-gnu-gcc -static -O2 -Wall -o "$ROOT/build/qmi-sns" "$ROOT/tools/qmi-sns/qmi-sns.c"
file "$ROOT/build/qmi-sns"
