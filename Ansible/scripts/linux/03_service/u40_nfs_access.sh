#!/bin/bash
# U-40 NFS 접근 통제
# 사용법: ./u40_nfs_access.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U40
    ;;
  fix)
    if declare -F fix_U40 > /dev/null; then
      fix_U40
      check_U40
    else
      check_U40
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
