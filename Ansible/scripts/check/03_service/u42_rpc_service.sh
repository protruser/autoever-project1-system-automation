#!/bin/bash
# U-42 불필요한 RPC 서비스 비활성화
# 사용법: ./u42_rpc_service.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U42
    ;;
  fix)
    if declare -F fix_U42 > /dev/null; then
      fix_U42
      check_U42
    else
      check_U42
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
