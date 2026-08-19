#!/bin/bash
# U-64 주기적 보안 패치 및 벤더 권고사항 적용
# 사용법: ./u64_os_patch.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U64
    ;;
  fix)
    if declare -F fix_U64 > /dev/null; then
      fix_U64
      check_U64
    else
      check_U64
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
