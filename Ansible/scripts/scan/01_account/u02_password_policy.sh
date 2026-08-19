#!/bin/bash
# U-02 비밀번호 관리정책 설정
# 사용법: ./u02_password_policy.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U02
    ;;
  fix)
    if declare -F fix_U02 > /dev/null; then
      fix_U02
      check_U02
    else
      check_U02
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
