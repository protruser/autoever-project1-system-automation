#!/bin/bash
# U-39 불필요한 NFS 서비스 비활성화
# 사용법: ./u39_nfs.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U39
    ;;
  fix)
    if declare -F fix_U39 > /dev/null; then
      fix_U39
      check_U39
    else
      check_U39
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
