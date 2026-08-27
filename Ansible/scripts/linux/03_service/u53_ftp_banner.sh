#!/bin/bash
# U-53 FTP 서비스 정보 노출 제한
# 사용법: ./u53_ftp_banner.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U53
    ;;
  fix)
    if declare -F fix_U53 > /dev/null; then
      fix_U53
      check_U53
    else
      check_U53
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
