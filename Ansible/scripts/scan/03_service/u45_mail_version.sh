#!/bin/bash
# U-45 메일 서비스 버전 점검
# 사용법: ./u45_mail_version.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U45
    ;;
  fix)
    if declare -F fix_U45 > /dev/null; then
      fix_U45
      check_U45
    else
      check_U45
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
