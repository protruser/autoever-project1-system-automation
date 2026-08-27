#!/bin/bash
# U-13 안전한 비밀번호 암호화 알고리즘 사용
# 사용법: ./u13_password_encrypt.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U13
    ;;
  fix)
    if declare -F fix_U13 > /dev/null; then
      fix_U13
      check_U13
    else
      check_U13
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
