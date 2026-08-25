#!/bin/bash
# fixes.sh - items.sh에서 자동조치(1)로 표시된 항목의 조치(fix) 함수.
# 모든 함수는 변경 전 backup_file()로 원본을 백업한 뒤 '최소한의 변경'만 수행한다.

fix_U01() {
  # [MOD] code/autofix_flag 가드 추가, OS_ID에 따라 sshd/ssh 서비스명 분기 추가
  local code="U-01"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  local f="/etc/ssh/sshd_config"
  backup_file "$f"
  if grep -Eqi '^\s*PermitRootLogin' "$f"; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*PermitRootLogin.*/PermitRootLogin no/I' "$f"
  else
    echo "PermitRootLogin no" >> "$f"
  fi
 
  # restart가 아니라 reload를 쓴다 - restart는 sshd 데몬을 내렸다 올리는 거라,
  # 그 찰나에 이 fix 바로 다음 항목의 SSH 연결(Ansible이 같은 접속을 재사용/
  # 재시도)이 걸리면 실패로 잡힐 수 있다. reload는 데몬을 안 내리고 SIGHUP으로
  # 설정만 다시 읽는데, PermitRootLogin은 reload로도 정상 반영되는 설정이라
  # 굳이 restart를 쓸 이유가 없다.
  # 전역 변수 $OS_ID 참조 (Ubuntu는 ssh, Rocky/RHEL 계열은 sshd 서비스명 사용)
  if [ "$OS_ID" = "ubuntu" ]; then
    systemctl reload ssh 2>/dev/null
  else
    systemctl reload sshd 2>/dev/null
  fi
}
 
fix_U02() {
  # [MOD] code/autofix_flag 가드 추가
  local code="U-02"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  backup_file /etc/login.defs
  backup_file /etc/security/pwquality.conf
  grep -q '^PASS_MAX_DAYS' /etc/login.defs && sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs || echo "PASS_MAX_DAYS   90" >> /etc/login.defs
  if [ -f /etc/security/pwquality.conf ]; then
    grep -q '^minlen' /etc/security/pwquality.conf && sed -i 's/^minlen.*/minlen = 8/' /etc/security/pwquality.conf || echo "minlen = 8" >> /etc/security/pwquality.conf
  fi
}
 
fix_U03() {
  # [MOD] code/autofix_flag 가드 추가
  local code="U-03"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  local f="/etc/security/faillock.conf"
  backup_file "$f"
  grep -q '^deny =' "$f" 2>/dev/null && sed -i 's/^deny =.*/deny = 5/' "$f" || echo "deny = 5" >> "$f"
}
 
fix_U04() {
  # [MOD] code/autofix_flag 가드 추가
  local code="U-04"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  pwconv 2>/dev/null
}

fix_U05() {
  local code="U-05"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local passwd_file="/etc/passwd"
  [ -f "$passwd_file" ] || return 0

  # UID가 0이면서 계정명이 'root'가 아닌 사용자 목록 추출
  local rogue_users
  rogue_users=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' "$passwd_file")

  [ -z "$rogue_users" ] && return 0

  backup_file "$passwd_file"

  # 시스템 내 미사용 UID 할당을 위한 기준값 (최대 UID + 1 또는 기본 1000)
  local max_uid
  max_uid=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' "$passwd_file" | sort -n | tail -1)
  [ -z "$max_uid" ] && max_uid=1000

  for user in $rogue_users; do
    max_uid=$((max_uid + 1))

    # 1차: usermod 명령어로 UID 변경 시도
    if ! usermod -u "$max_uid" "$user" 2>/dev/null; then
      # 프로세스 점유 등으로 실패 시 /etc/passwd 직접 수정
      sed -i -E "s/^(${user}:[^:]*):0:/\1:${max_uid}:/" "$passwd_file"
    fi
  done
}

fix_U06() {
  # [MOD] code/autofix_flag 가드 추가
  local code="U-06"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  local f="/etc/pam.d/su"
  backup_file "$f"
  grep -Eq '^\s*auth\s+required\s+pam_wheel\.so' "$f" || sed -i '/pam_rootok.so/a auth            required        pam_wheel.so use_uid' "$f"
}

fix_U07() {
  local code="U-07"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local passwd_file="/etc/passwd"
  [ -f "$passwd_file" ] || return 0

  # 보안 가이드 및 진단 기준 불필요 기본 계정 목록
  local default_unused_accounts="lp uucp nuucp games news gopher sync shutdown halt"

  local target_found=0
  for account in $default_unused_accounts; do
    if grep -Eq "^${account}:" "$passwd_file" 2>/dev/null; then
      target_found=1
      break
    fi
  done

  # 조치 대상 계정이 시스템에 없으면 종료
  [ "$target_found" -eq 0 ] && return 0

  backup_file "$passwd_file"
  [ -f "/etc/shadow" ] && backup_file "/etc/shadow"
  [ -f "/etc/group" ] && backup_file "/etc/group"

  for account in $default_unused_accounts; do
    if grep -Eq "^${account}:" "$passwd_file" 2>/dev/null; then
      # userdel을 통한 계정 삭제 시도 (홈 디렉터리 보존을 위해 -r 옵션 미사용)
      if ! userdel "$account" 2>/dev/null; then
        # userdel 실패 시 passwd, shadow, group 파일에서 직접 제거
        sed -i -E "/^${account}:/d" "$passwd_file"
        [ -f "/etc/shadow" ] && sed -i -E "/^${account}:/d" /etc/shadow
        [ -f "/etc/group" ] && sed -i -E "/^${account}:/d" /etc/group
      fi
    fi
  done
}

fix_U08() {
  local code="U-08"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local group_file="/etc/group"
  [ -f "$group_file" ] || return 0

  # root 그룹(GID 0) 라인 추출 (형식: root:x:0:user1,user2,...)
  local root_group_line
  root_group_line=$(grep -E '^root:[^:]*:0:' "$group_file" 2>/dev/null)

  [ -z "$root_group_line" ] && return 0

  # 4번째 필드(그룹 멤버 목록) 파싱
  local members
  members=$(echo "$root_group_line" | awk -F: '{print $4}')

  [ -z "$members" ] && return 0

  # root 이외의 계정 목록 필터링
  local rogue_members=""
  IFS=',' read -r -a member_array <<< "$members"
  for user in "${member_array[@]}"; do
    user=$(echo "$user" | tr -d ' ')
    if [ -n "$user" ] && [ "$user" != "root" ]; then
      rogue_members="$rogue_members $user"
    fi
  done

  # root 외에 다른 계정이 없으면 종료
  [ -z "$rogue_members" ] && return 0

  backup_file "$group_file"

  # 불필요 계정 제거 수행
  for user in $rogue_members; do
    if ! gpasswd -d "$user" root 2>/dev/null; then
      # gpasswd 실패 시 /etc/group 직접 치환 (콤마 및 단어 경계 처리)
      sed -i -E \
        -e "/^root:[^:]*:0:/ s/(,)?\<${user}\>(,)?/\1\2/g" \
        -e "/^root:[^:]*:0:/ s/::/:/g" \
        -e "/^root:[^:]*:0:/ s/:,/:/g" \
        -e "/^root:[^:]*:0:/ s/,$//g" \
        "$group_file"
    fi
  done
}

fix_U09() {
  local code="U-09"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local group_file="/etc/group"
  local passwd_file="/etc/passwd"
  [ -f "$group_file" ] && [ -f "$passwd_file" ] || return 0

  # OS 및 시스템 동작에 필수적인 시스템 예약 기본 그룹 (보호 대상)
  local protected_groups="root bin daemon sys adm tty disk lp mail uucp man proxy kmem dialout fax voice cdrom floppy tape sudo audio dip operator src shadow utmp video sasl plugdev staff games users nogroup nobody systemd-journal systemd-network systemd-resolve systemd-timesync kvm input render crontab sshd netdev"

  # 1. 현재 /etc/passwd에서 주 그룹(GID)으로 사용 중인 GID 목록 추출
  local used_gids
  used_gids=$(awk -F: '{print $4}' "$passwd_file" | sort -u)

  # 2. 미사용 대상 그룹 검색
  local groups_to_delete=""
  while IFS=: read -r group_name pass gid members; do
    [ -z "$group_name" ] && continue

    # 시스템 보호 그룹은 제외
    if echo " $protected_groups " | grep -q " $group_name "; then
      continue
    fi

    # /etc/passwd의 주 그룹으로 사용 중이면 유지
    if echo "$used_gids" | grep -qx "$gid"; then
      continue
    fi

    # /etc/group의 4번째 필드(보조 멤버)에 계정이 등록되어 있으면 유지
    if [ -n "$members" ]; then
      continue
    fi

    groups_to_delete="$groups_to_delete $group_name"
  done < "$group_file"

  [ -z "$groups_to_delete" ] && return 0

  backup_file "$group_file"
  [ -f "/etc/gshadow" ] && backup_file "/etc/gshadow"

  # 3. 미사용 그룹 제거 수행
  for g in $groups_to_delete; do
    if ! groupdel "$g" 2>/dev/null; then
      # groupdel 실패 시 설정 파일에서 직접 제거
      sed -i -E "/^${g}:/d" "$group_file"
      [ -f "/etc/gshadow" ] && sed -i -E "/^${g}:/d" /etc/gshadow
    fi
  done
}

fix_U10() {
  local code="U-10"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local passwd_file="/etc/passwd"
  [ -f "$passwd_file" ] || return 0

  # 중복된 UID 목록 추출 (UID가 2회 이상 등장하는 UID 값들)
  local dup_uids
  dup_uids=$(awk -F: '{print $3}' "$passwd_file" | sort -n | uniq -d)

  [ -z "$dup_uids" ] && return 0

  backup_file "$passwd_file"

  # 시스템 내 미사용 UID 할당을 위한 기준 최댓값 계산
  local max_uid
  max_uid=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' "$passwd_file" | sort -n | tail -1)
  [ -z "$max_uid" ] && max_uid=1000

  for uid in $dup_uids; do
    # 해당 중복 UID를 사용하는 모든 계정 목록 추출
    local users
    users=$(awk -F: -v target_uid="$uid" '$3 == target_uid {print $1}' "$passwd_file")

    local is_first=1
    for user in $users; do
      # 첫 번째 계정(또는 root 계정)은 기존 UID를 유지하고, 나머지 중복 계정들의 UID를 변경
      if [ "$is_first" -eq 1 ] && [ "$user" = "root" -o "$uid" != "0" ]; then
        is_first=0
        continue
      fi
      is_first=0

      max_uid=$((max_uid + 1))

      # 1차: usermod 명령어로 고유 UID 부여 시도
      if ! usermod -u "$max_uid" "$user" 2>/dev/null; then
        # 프로세스 점유 등으로 실패 시 /etc/passwd 직접 치환
        sed -i -E "s/^(${user}:[^:]*):${uid}:/\1:${max_uid}:/" "$passwd_file"
      fi
    done
  done
}

fix_U11() {
  local code="U-11"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local passwd_file="/etc/passwd"
  [ -f "$passwd_file" ] || return 0

  # 시스템 환경에 따른 nologin 쉘 경로 지정
  local nologin_shell="/sbin/nologin"
  if [ ! -x "$nologin_shell" ]; then
    if [ -x "/usr/sbin/nologin" ]; then
      nologin_shell="/usr/sbin/nologin"
    else
      nologin_shell="/bin/false"
    fi
  fi

  # 가이드 기준 로그인이 불필요한 기본 계정 목록
  local no_login_accounts="daemon bin sys adm listen nobody nobody4 noaccess diag operator games gopher"

  # 변경 대상 계정 식별 (nologin 또는 false 계열이 아닌 쉘을 가진 계정)
  local target_users=""
  for acc in $no_login_accounts; do
    local user_line
    user_line=$(grep -E "^${acc}:" "$passwd_file" 2>/dev/null)
    [ -z "$user_line" ] && continue

    local current_shell
    current_shell=$(echo "$user_line" | awk -F: '{print $7}')

    # 이미 /sbin/nologin, /usr/sbin/nologin, /bin/false 등으로 설정된 경우 제외
    if ! echo "$current_shell" | grep -Eq '(nologin|false)$'; then
      target_users="$target_users $acc"
    fi
  done

  [ -z "$target_users" ] && return 0

  backup_file "$passwd_file"

  # 쉘 변경 조치 수행
  for user in $target_users; do
    if ! usermod -s "$nologin_shell" "$user" 2>/dev/null; then
      # usermod 실패 시 /etc/passwd 직접 치환
      sed -i -E "s|^(${user}:([^:]*:){5})[^:]*$|\1${nologin_shell}|" "$passwd_file"
    fi
  done
}

fix_U12() {
  # [MOD] code/autofix_flag 가드 추가
  local code="U-12"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  local f="/etc/profile.d/tmout.sh"
  echo 'TMOUT=600' > "$f"
  echo 'readonly TMOUT' >> "$f"
  echo 'export TMOUT' >> "$f"
  chmod 644 "$f"
}
 
fix_U13() {
  # [MOD] code/autofix_flag 가드 추가
  local code="U-13"
  local autofix_flag="$(get_item_autofix "$code")"
  [ "$autofix_flag" != "1" ] && return 0
 
  backup_file /etc/login.defs
  grep -q '^ENCRYPT_METHOD' /etc/login.defs && sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs || echo "ENCRYPT_METHOD SHA512" >> /etc/login.defs
}

fix_U14() {
  local code="U-14"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local targets=()

  if [ "$OS_ID" = "ubuntu" ]; then
    targets=("/etc/environment" "/etc/profile" "/etc/bash.bashrc" "/root/.profile" "/root/.bashrc")
  else
    targets=("/etc/profile" "/etc/bashrc" "/root/.bash_profile" "/root/.bashrc")
  fi

  for f in "${targets[@]}"; do
    [ -f "$f" ] || continue
    # PATH 선언문 내에 맨 앞/중간 '.' 또는 '::'가 존재하는지 점검
    if grep -Eq 'PATH=.*(^\.:|:\.:|^:|::|\.\:)' "$f" 2>/dev/null; then
      backup_file "$f"
      # 콜론 정규화 및 중간/맨 앞 . 제거
      sed -i -E 's/(^|:)\.(:|$)/:/g; s/::+/:/g; s/^://; s/:$//' "$f"
    fi
  done
}


fix_U15() {
  local code="U-15"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 소유자 또는 그룹이 없는 모든 파일/디렉터리의 소유권을 안전하게 root:root로 일괄 이관
  find / -xdev \( -nouser -o -nogroup \) -exec chown root:root {} + 2>/dev/null
  generate_cache "U-15"
}


fix_U16() {
  local code="U-16"
  local autofix_flag="$(get_item_autofix "$code")"
  local target_file="/etc/passwd"

  [ "$autofix_flag" != "1" ] && return 0
  [ -f "$target_file" ] || return 0

  backup_file "$target_file"
  chown root "$target_file" 2>/dev/null
  chmod 644 "$target_file" 2>/dev/null
}


fix_U17() {
  local code="U-17"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local check_dirs=()

  if [ "$OS_ID" = "ubuntu" ]; then
    for d in /etc/init.d /etc/rc*.d /etc/systemd/system; do
      [ -d "$d" ] && check_dirs+=("$d")
    done
  else
    for d in /etc/rc.d /etc/init.d /etc/systemd/system; do
      [ -d "$d" ] && check_dirs+=("$d")
    done
  fi

  # 소유자 root 변경 및 other 쓰기 권한 제거
  if [ ${#check_dirs[@]} -gt 0 ]; then
    find "${check_dirs[@]}" -type f \( ! -user root -o -perm -002 \) -exec chown root:root {} + -exec chmod o-w {} + 2>/dev/null
  fi
}


fix_U18() {
  local code="U-18"
  local autofix_flag="$(get_item_autofix "$code")"
  local target_file="/etc/shadow"

  [ "$autofix_flag" != "1" ] && return 0
  [ -f "$target_file" ] || return 0

  backup_file "$target_file"
  chown root "$target_file" 2>/dev/null
  chmod 400 "$target_file" 2>/dev/null
}


fix_U19() {
  local code="U-19"
  local autofix_flag="$(get_item_autofix "$code")"
  local target_file="/etc/hosts"

  [ "$autofix_flag" != "1" ] && return 0
  [ -f "$target_file" ] || return 0

  backup_file "$target_file"
  chown root "$target_file" 2>/dev/null
  chmod 644 "$target_file" 2>/dev/null
}


fix_U20() {
  local code="U-20"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # inetd.conf 조치
  if [ -f /etc/inetd.conf ]; then
    backup_file "/etc/inetd.conf"
    chown root /etc/inetd.conf 2>/dev/null
    chmod 600 /etc/inetd.conf 2>/dev/null
  fi

  # xinetd.conf 조치
  if [ -f /etc/xinetd.conf ]; then
    backup_file "/etc/xinetd.conf"
    chown root /etc/xinetd.conf 2>/dev/null
    chmod 600 /etc/xinetd.conf 2>/dev/null
  fi

  # xinetd.d 내부 파일 조치
  if [ -d /etc/xinetd.d ]; then
    find /etc/xinetd.d -type f | while read -r f; do
      backup_file "$f"
    done
    chown -R root /etc/xinetd.d 2>/dev/null
    chmod -R 600 /etc/xinetd.d 2>/dev/null
  fi
}


fix_U21() {
  local code="U-21"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # /etc/rsyslog.conf 조치
  if [ -f /etc/rsyslog.conf ]; then
    backup_file "/etc/rsyslog.conf"
    chown root /etc/rsyslog.conf 2>/dev/null
    chmod 640 /etc/rsyslog.conf 2>/dev/null
  fi

  # /etc/syslog.conf 조치
  if [ -f /etc/syslog.conf ]; then
    backup_file "/etc/syslog.conf"
    chown root /etc/syslog.conf 2>/dev/null
    chmod 640 /etc/syslog.conf 2>/dev/null
  fi

  # /etc/rsyslog.d 내부 설정 파일 조치
  if [ -d /etc/rsyslog.d ]; then
    find /etc/rsyslog.d -type f | while IFS= read -r f; do
      backup_file "$f"
      chown root "$f" 2>/dev/null
      chmod 640 "$f" 2>/dev/null
    done
  fi
}


fix_U22() {
  local code="U-22"
  local autofix_flag="$(get_item_autofix "$code")"
  local target_file="/etc/services"

  [ "$autofix_flag" != "1" ] && return 0
  [ -f "$target_file" ] || return 0

  backup_file "$target_file"
  chown root "$target_file" 2>/dev/null
  chmod 644 "$target_file" 2>/dev/null
}


fix_U23() {
  local code="U-23"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local risky_bins=(
    "/sbin/dump" "/sbin/restore" "/sbin/unix_chkpwd"
    "/usr/bin/at" "/usr/bin/lp" "/usr/bin/lpr" "/usr/bin/lprm"
    "/usr/bin/newgrp" "/usr/bin/rcp" "/usr/bin/rlogin" "/usr/bin/rsh"
    "/usr/bin/traceroute" "/usr/bin/wall" "/usr/bin/write"
    "/usr/sbin/dump" "/usr/sbin/restore" "/usr/sbin/lpc" "/usr/sbin/traceroute"
  )

  for f in "${risky_bins[@]}"; do
    if [ -f "$f" ]; then
      if [ -u "$f" ] || [ -g "$f" ]; then
        chmod -s "$f" 2>/dev/null
      fi
    fi
  done
}


fix_U24() {
  local code="U-24"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local env_files=(".profile" ".bashrc" ".bash_profile" ".bash_login" ".kshrc" ".cshrc" ".login" ".exrc" ".netrc")

  while IFS=: read -r user _ _ _ _ home shell; do
    [ -d "$home" ] || continue
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    for ef in "${env_files[@]}"; do
      local target_path="${home}/${ef}"
      if [ -f "$target_path" ]; then
        local owner perm
        owner=$(owner_of "$target_path")
        perm=$(perm_octal "$target_path")

        local need_fix=0
        if [ "$owner" != "$user" ] && [ "$owner" != "root" ]; then
          need_fix=1
        elif [ -n "$perm" ] && [ "$(( 8#$perm & 8#002 ))" -ne 0 ]; then
          need_fix=1
        fi

        if [ "$need_fix" -eq 1 ]; then
          backup_file "$target_path"
          chown "$user" "$target_path" 2>/dev/null
          chmod o-w "$target_path" 2>/dev/null
        fi
      fi
    done
  done < /etc/passwd
}


fix_U25() {
  local code="U-25"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 시스템 루트 파일시스템 내 불필요한 World Writable 파일의 other 쓰기 권한 일괄 제거
  find / -xdev -type f -perm -002 -exec chmod o-w {} + 2>/dev/null
  generate_cache "U-25"
}


fix_U26() {
  local code="U-26"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # /dev 내 비정상 일반 파일 검색 및 안전 백업 후 삭제
  find /dev -type f ! -path '/dev/shm/*' ! -path '/dev/mqueue/*' 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    backup_file "$f"
    rm -f "$f" 2>/dev/null
  done
}


fix_U27() {
  local code="U-27"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # /etc/hosts.equiv 조치
  if [ -f /etc/hosts.equiv ]; then
    backup_file "/etc/hosts.equiv"
    chown root:root /etc/hosts.equiv 2>/dev/null
    chmod 600 /etc/hosts.equiv 2>/dev/null
    sed -i '/+/d' /etc/hosts.equiv 2>/dev/null
  fi

  # ~/.rhosts 조치
  while IFS=: read -r user _ _ _ _ home shell; do
    [ -d "$home" ] || continue
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    local rhost_file="$home/.rhosts"
    if [ -f "$rhost_file" ]; then
      backup_file "$rhost_file"
      chown "$user" "$rhost_file" 2>/dev/null
      chmod 600 "$rhost_file" 2>/dev/null
      sed -i '/+/d' "$rhost_file" 2>/dev/null
    fi
  done < /etc/passwd
}


fix_U28() {
  local code="U-28"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 원격 차단(Lockout) 방지를 위해 SSH 포트를 안전하게 열어두며 활성화
  if [ "$OS_ID" = "ubuntu" ]; then
    if command -v ufw &>/dev/null; then
      ufw allow 22/tcp 2>/dev/null
      ufw --force enable 2>/dev/null
    else
      # TCP Wrapper 폴백 설정
      [ -f /etc/hosts.deny ] && backup_file "/etc/hosts.deny"
      echo "ALL: ALL" >> /etc/hosts.deny
      [ -f /etc/hosts.allow ] && backup_file "/etc/hosts.allow"
      echo "sshd: ALL" >> /etc/hosts.allow
    fi
  else
    if command -v firewall-cmd &>/dev/null; then
      systemctl enable --now firewalld 2>/dev/null
      firewall-cmd --permanent --add-service=ssh 2>/dev/null
      firewall-cmd --reload 2>/dev/null
    else
      # TCP Wrapper 폴백 설정
      [ -f /etc/hosts.deny ] && backup_file "/etc/hosts.deny"
      echo "ALL: ALL" >> /etc/hosts.deny
      [ -f /etc/hosts.allow ] && backup_file "/etc/hosts.allow"
      echo "sshd: ALL" >> /etc/hosts.allow
    fi
  fi
}


fix_U29() {
  local code="U-29"
  local autofix_flag="$(get_item_autofix "$code")"
  local target_file="/etc/hosts.lpd"

  [ "$autofix_flag" != "1" ] && return 0
  [ -f "$target_file" ] || return 0

  backup_file "$target_file"
  chown root "$target_file" 2>/dev/null
  chmod 600 "$target_file" 2>/dev/null
}


fix_U30() {
  local code="U-30"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 1. /etc/login.defs 수정
  if [ -f /etc/login.defs ]; then
    backup_file "/etc/login.defs"
    if grep -Eqi '^[[:space:]]*UMASK' /etc/login.defs; then
      sed -i -E 's/^([[:space:]]*UMASK[[:space:]]+)[0-9]+/UMASK\t022/I' /etc/login.defs
    else
      echo -e "\nUMASK\t022" >> /etc/login.defs
    fi
  fi

  # 2. /etc/profile 수정
  if [ -f /etc/profile ]; then
    backup_file "/etc/profile"
    if grep -Eq '^[[:space:]]*umask' /etc/profile; then
      sed -i -E 's/^[[:space:]]*umask[[:space:]]+[0-9]+/umask 022/' /etc/profile
    else
      echo -e "\numask 022\nexport umask" >> /etc/profile
    fi
  fi

  # 3. OS별 서브 프로필 쉘 설정 (/etc/bashrc 또는 /etc/bash.bashrc)
  if [ "$OS_ID" = "ubuntu" ]; then
    if [ -f /etc/bash.bashrc ]; then
      backup_file "/etc/bash.bashrc"
      if grep -Eq '^[[:space:]]*umask' /etc/bash.bashrc; then
        sed -i -E 's/^[[:space:]]*umask[[:space:]]+[0-9]+/umask 022/' /etc/bash.bashrc
      fi
    fi
  else
    if [ -f /etc/bashrc ]; then
      backup_file "/etc/bashrc"
      if grep -Eq '^[[:space:]]*umask' /etc/bashrc; then
        sed -i -E 's/^[[:space:]]*umask[[:space:]]+[0-9]+/umask 022/' /etc/bashrc
      fi
    fi
  fi
}

fix_U31() {
  local code="U-31"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  while IFS=: read -r user _ _ _ _ home shell; do
    [ -d "$home" ] || continue
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    # 루트(/) 디렉터리가 홈으로 잡혀있는 특수 계정의 오동작 방지
    [ "$home" = "/" ] && continue

    local owner perm
    owner=$(owner_of "$home")
    perm=$(perm_octal "$home")

    local need_fix=0
    if [ "$owner" != "$user" ] && [ "$owner" != "root" ]; then
      need_fix=1
    elif [ -n "$perm" ] && [ "$(( 8#$perm & 8#002 ))" -ne 0 ]; then
      need_fix=1
    fi

    if [ "$need_fix" -eq 1 ]; then
      chown "$user" "$home" 2>/dev/null
      chmod o-w "$home" 2>/dev/null
    fi
  done < /etc/passwd
}

fix_U32() {
  local code="U-32"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  while IFS=: read -r user _ _ gid _ home shell; do
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    # 홈 디렉터리가 미존재하는 경우 안전하게 디렉터리 생성 및 700 권한 부여
    if [ -n "$home" ] && [ ! -d "$home" ]; then
      # 루트(/) 예외 방어
      [ "$home" = "/" ] && continue

      mkdir -p "$home" 2>/dev/null
      chown "${user}:${gid}" "$home" 2>/dev/null
      chmod 700 "$home" 2>/dev/null

      # OS별 기본 skel 파일 배포
      if [ -d /etc/skel ]; then
        cp -rn /etc/skel/. "$home/" 2>/dev/null
        chown -R "${user}:${gid}" "$home" 2>/dev/null
      fi
    fi
  done < /etc/passwd
}


fix_U33() {
  local code="U-33"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 정상 숨김 파일 오삭제 방지: 공백을 포함하거나 '...' 등 명백한 위장 숨김 파일만 안전 격리/삭제
  find /tmp /var/tmp /dev/shm -maxdepth 2 \( -name '..*' -o -name '. *' -o -name '...*' \) ! -name '.' ! -name '..' 2>/dev/null | while IFS= read -r f; do
    [ -e "$f" ] || continue
    backup_file "$f"
    rm -rf "$f" 2>/dev/null
  done
  generate_cache "U-33"
}



fix_U34() {
  local code="U-34"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # finger 서비스 중지 및 비활성화 (systemd 서비스로 존재하는 경우)
  svc_exists "finger" && systemctl stop finger 2>/dev/null
  svc_exists "finger" && systemctl disable finger 2>/dev/null

  # 전역 변수 $OS_ID 참조 (xinetd 설정 위치는 Ubuntu/Rocky 동일하게 /etc/xinetd.d/finger 사용)
  if [ -f /etc/xinetd.d/finger ]; then
    backup_file /etc/xinetd.d/finger
    sed -i -E 's/(disable[[:space:]]*=[[:space:]]*)no/\1yes/' /etc/xinetd.d/finger
    if [ "$OS_ID" = "ubuntu" ]; then
      systemctl restart xinetd 2>/dev/null
    else
      systemctl restart xinetd 2>/dev/null
    fi
  fi
  generate_cache "SVC"
}
###
# 0820 U-48~63 정진우

fix_U35() {
  local code="U-35"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local f

  # 전역 변수 $OS_ID 참조 (vsftpd 설정 파일 경로가 배포판별로 다름)
  if [ "$OS_ID" = "ubuntu" ]; then
    f="/etc/vsftpd.conf"
  else
    f="/etc/vsftpd/vsftpd.conf"
  fi

  if [ -f "$f" ]; then
    backup_file "$f"
    if grep -Eq '^\s*anonymous_enable\s*=' "$f"; then
      sed -i -E 's/^\s*anonymous_enable\s*=.*/anonymous_enable=NO/I' "$f"
    else
      echo "anonymous_enable=NO" >> "$f"
    fi
    svc_exists "vsftpd" && systemctl restart vsftpd 2>/dev/null
  fi

  if [ -f /etc/samba/smb.conf ]; then
    backup_file /etc/samba/smb.conf
    sed -i -E 's/(guest ok[[:space:]]*=[[:space:]]*)yes/\1no/I' /etc/samba/smb.conf
    if [ "$OS_ID" = "ubuntu" ]; then
      svc_exists "smbd" && systemctl restart smbd 2>/dev/null
    else
      svc_exists "smb" && systemctl restart smb 2>/dev/null
    fi
  fi

  getent passwd ftp >/dev/null 2>&1 && userdel ftp 2>/dev/null
  getent passwd anonymous >/dev/null 2>&1 && userdel anonymous 2>/dev/null
}

fix_U36() {
  local code="U-36"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local svc f

  for svc in rsh rlogin rexec; do
    svc_exists "$svc" && systemctl stop "$svc" 2>/dev/null
    svc_exists "$svc" && systemctl disable "$svc" 2>/dev/null
  done

  # 전역 변수 $OS_ID 참조 (xinetd 파일 경로는 동일, 재시작 방식만 구분)
  for f in /etc/xinetd.d/rsh /etc/xinetd.d/rlogin /etc/xinetd.d/rexec; do
    [ -f "$f" ] || continue
    backup_file "$f"
    sed -i -E 's/(disable[[:space:]]*=[[:space:]]*)no/\1yes/' "$f"
  done
  if [ "$OS_ID" = "ubuntu" ]; then
    svc_exists "xinetd" && systemctl restart xinetd 2>/dev/null
  else
    svc_exists "xinetd" && systemctl restart xinetd 2>/dev/null
  fi

  [ -f /etc/hosts.equiv ] && { backup_file /etc/hosts.equiv; chmod 600 /etc/hosts.equiv; }
  [ -f /root/.rhosts ] && { backup_file /root/.rhosts; chmod 600 /root/.rhosts; }
  generate_cache "SVC"
}

fix_U37() {
  local code="U-37"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  chmod 750 /usr/bin/crontab 2>/dev/null
  chmod 750 /usr/bin/at 2>/dev/null
  [ -f /etc/crontab ] && chmod 640 /etc/crontab 2>/dev/null

  # 전역 변수 $OS_ID 참조 (사용자별 cron 작업 목록 저장 경로가 배포판별로 다름)
  local spool_dir
  if [ "$OS_ID" = "ubuntu" ]; then
    spool_dir="/var/spool/cron/crontabs"
  else
    spool_dir="/var/spool/cron"
  fi

  find /etc/cron.d "$spool_dir" -type f 2>/dev/null | while read -r f; do
    chmod 640 "$f" 2>/dev/null
  done
}

fix_U38() {
  local code="U-38"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local svc f

  for svc in echo discard daytime chargen; do
    svc_exists "$svc" && systemctl stop "$svc" 2>/dev/null
    svc_exists "$svc" && systemctl disable "$svc" 2>/dev/null
  done

  for f in /etc/xinetd.d/echo /etc/xinetd.d/echo-udp /etc/xinetd.d/discard /etc/xinetd.d/discard-udp \
           /etc/xinetd.d/daytime /etc/xinetd.d/daytime-udp /etc/xinetd.d/chargen /etc/xinetd.d/chargen-udp; do
    [ -f "$f" ] || continue
    backup_file "$f"
    sed -i -E 's/(disable[[:space:]]*=[[:space:]]*)no/\1yes/' "$f"
  done

  # 전역 변수 $OS_ID 참조
  if [ "$OS_ID" = "ubuntu" ]; then
    svc_exists "xinetd" && systemctl restart xinetd 2>/dev/null
  else
    svc_exists "xinetd" && systemctl restart xinetd 2>/dev/null
  fi
  generate_cache "SVC"
}

fix_U39() {
  local code="U-39"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  svc_disable_now "nfs-server"
  generate_cache "SVC"
}

fix_U40() {
  local code="U-40"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  [ -f /etc/exports ] || return 0

  backup_file /etc/exports
  chown root:root /etc/exports 2>/dev/null
  chmod 644 /etc/exports 2>/dev/null

  # no_root_squash, 와일드카드(*) 호스트 허용 등은 서비스 영향이 커서
  # 자동으로 값을 바꾸지 않고 백업만 남겨 관리자가 직접 검토하도록 함
}

fix_U41() {
  local code="U-41"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  svc_disable_now "autofs"
  generate_cache "SVC"
}

fix_U42() {
  local code="U-42"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local svc
  for svc in rusersd rwalld sprayd rstatd rquotad nfs-rquotad; do
    svc_disable_now "$svc"
  done
  # rpcbind 자체는 NFS 등 정상 서비스에 필요할 수 있어 자동으로 비활성화하지 않음
  generate_cache "SVC"
}

fix_U43() {
  local code="U-43"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local svc
  for svc in ypserv ypbind ypxfrd yppasswdd ypupdated; do
    svc_disable_now "$svc"
  done
  generate_cache "SVC"
}

fix_U44() {
  local code="U-44"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local svc f

  for svc in tftp talk ntalk; do
    svc_exists "$svc" && systemctl stop "$svc" 2>/dev/null
    svc_exists "$svc" && systemctl disable "$svc" 2>/dev/null
  done

  for f in /etc/xinetd.d/tftp /etc/xinetd.d/talk /etc/xinetd.d/ntalk; do
    [ -f "$f" ] || continue
    backup_file "$f"
    sed -i -E 's/(disable[[:space:]]*=[[:space:]]*)no/\1yes/' "$f"
  done

  # 전역 변수 $OS_ID 참조
  if [ "$OS_ID" = "ubuntu" ]; then
    svc_exists "xinetd" && systemctl restart xinetd 2>/dev/null
  else
    svc_exists "xinetd" && systemctl restart xinetd 2>/dev/null
  fi

  generate_cache "SVC"
}

fix_U45() {
  local code="U-45"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 메일 서비스 버전 업그레이드/패치는 서비스 영향도가 커서 자동 조치 대상에서 제외.
  # (자동조치 미지원 항목: items.sh에서 U-45의 autofix를 0으로 등록해두었으므로
  #  이 함수는 사실상 위 가드에서 항상 return 0 됨)
  return 0
}

fix_U46() {
  local code="U-46"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  [ -x /usr/sbin/postsuper ] && chmod o-x /usr/sbin/postsuper 2>/dev/null
  [ -x /usr/sbin/exiqgrep ] && chmod o-x /usr/sbin/exiqgrep 2>/dev/null

  if [ -f /etc/mail/sendmail.cf ] && ! grep -q 'restrictqrun' /etc/mail/sendmail.cf 2>/dev/null; then
    backup_file /etc/mail/sendmail.cf
    sed -i -E 's/(PrivacyOptions[[:space:]]*=[[:space:]]*)(.*)/\1\2, restrictqrun/' /etc/mail/sendmail.cf
  fi
}

fix_U47() {
  local code="U-47"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 허용할 내부 네트워크 대역은 환경마다 달라 자동으로 안전하게 결정할 수 없으므로
  # 여기서는 설정을 변경하지 않고 백업만 남겨 관리자가 직접 mynetworks 값을 지정하도록 함.
  # (자동조치 미지원 항목: items.sh에서 U-47의 autofix를 0으로 등록해두었으므로
  #  이 함수는 사실상 위 가드에서 항상 return 0 됨)
  [ -f /etc/postfix/main.cf ] && backup_file /etc/postfix/main.cf
  return 0
}

fix_U48() {
  command -v postconf >/dev/null 2>&1 || return 0
  postconf -e "disable_vrfy_command=yes" 2>/dev/null
  systemctl reload postfix 2>/dev/null
}

fix_U49() { return 0; } # 수동 조치: DNS 서비스 업데이트
fix_U50() { return 0; } # 수동 조치: named.conf allow-transfer 제한
fix_U51() { return 0; } # 수동 조치: named.conf 동적 업데이트 제한

fix_U52() {
  if [ "$OS_ID" = "ubuntu" ]; then
    svc_disable_now inetutils-inetd 2>/dev/null
    svc_disable_now telnetd 2>/dev/null
  else
    svc_disable_now telnet.socket 2>/dev/null
  fi
  generate_cache "SVC"
}

fix_U53() {
  local f
  if [ "$OS_ID" = "ubuntu" ]; then
    f="/etc/vsftpd.conf"
  else
    f="/etc/vsftpd/vsftpd.conf"
  fi
  
  [ -f "$f" ] || return 0
  backup_file "$f"
  grep -qi '^\s*ftpd_banner' "$f" || echo 'ftpd_banner=Authorized access only.' >> "$f"
  systemctl restart vsftpd 2>/dev/null
}

fix_U54() { return 0; } # 수동 조치: FTP 서비스 비활성화 여부 결정

fix_U55() { 
  if [ "$OS_ID" = "ubuntu" ]; then
    getent passwd ftp >/dev/null 2>&1 && usermod -s /usr/sbin/nologin ftp
  else
    getent passwd ftp >/dev/null 2>&1 && usermod -s /sbin/nologin ftp
  fi
}

fix_U56() { return 0; } # 수동 조치: FTP 접근제어(TCP Wrappers/user_list) 확인

fix_U57() {
  local f
  if [ "$OS_ID" = "ubuntu" ]; then
    f="/etc/ftpusers"
  else
    f="/etc/vsftpd/ftpusers"
  fi

  [ -f "$f" ] || return 0
  backup_file "$f"
  grep -qx root "$f" || echo root >> "$f"
}

fix_U58() { 
  svc_disable_now snmpd 2>/dev/null
  generate_cache "SVC"
}

fix_U59() { return 0; } # 수동 조치: SNMPv3 사용 설정
fix_U60() { return 0; } # 수동 조치: SNMP community 문자열 변경
fix_U61() { return 0; } # 수동 조치: snmpd.conf ACL 허용 IP 설정

fix_U62() {
  local msg="Authorized users only. All activity may be monitored and reported."
  for f in /etc/motd /etc/issue /etc/issue.net; do
    backup_file "$f"
    echo "$msg" > "$f"
  done
}

fix_U63() { return 0; } # 수동 조치: /etc/sudoers 440 권한 확인
###

fix_U64() {
  local code="U-64"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 커널/패키지 전체 업데이트는 서비스 중단 위험이 커서 자동으로 실행하지 않고
  # 자동 보안 업데이트 "메커니즘"만 활성화한다. (items.sh에서 U-64의 autofix를
  # 0으로 등록해두면 이 함수는 사실상 위 가드에서 항상 return 0 됨)

  # 전역 변수 $OS_ID 참조
  if [ "$OS_ID" = "ubuntu" ]; then
    if ! svc_exists "unattended-upgrades"; then
      apt-get install -y unattended-upgrades 2>/dev/null
    fi
    systemctl enable --now unattended-upgrades 2>/dev/null
  else
    if ! svc_exists "dnf-automatic.timer"; then
      dnf install -y dnf-automatic 2>/dev/null
    fi
    systemctl enable --now dnf-automatic.timer 2>/dev/null
  fi
}

fix_U65() {
  local code="U-65"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  # 전역 변수 $OS_ID 참조 (Ubuntu/Rocky 모두 chrony를 사용하나 서비스명/설정 경로가 다름)
  if [ "$OS_ID" = "ubuntu" ]; then
    if ! svc_exists "chrony"; then
      apt-get install -y chrony 2>/dev/null
    fi
    if [ -f /etc/chrony/chrony.conf ] && ! grep -Eq '^\s*(server|pool)\s+\S+' /etc/chrony/chrony.conf 2>/dev/null; then
      backup_file /etc/chrony/chrony.conf
      echo "pool time.google.com iburst" >> /etc/chrony/chrony.conf
    fi
    systemctl enable --now chrony 2>/dev/null
  else
    if ! svc_exists "chronyd"; then
      dnf install -y chrony 2>/dev/null
    fi
    if [ -f /etc/chrony.conf ] && ! grep -Eq '^\s*(server|pool)\s+\S+' /etc/chrony.conf 2>/dev/null; then
      backup_file /etc/chrony.conf
      echo "pool time.google.com iburst" >> /etc/chrony.conf
    fi
    systemctl enable --now chronyd 2>/dev/null
  fi
}

fix_U66() {
  local code="U-66"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  local f="/etc/rsyslog.conf"

  # 전역 변수 $OS_ID 참조 (설정 파일 경로 자체는 동일하나, 배포판별 기본 패키지명이 다름)
  if [ "$OS_ID" = "ubuntu" ]; then
    svc_exists "rsyslog" || apt-get install -y rsyslog 2>/dev/null
  else
    svc_exists "rsyslog" || dnf install -y rsyslog 2>/dev/null
  fi

  if [ -f "$f" ]; then
    backup_file "$f"
    grep -Eq 'authpriv\.\*|auth,authpriv\.\*' "$f" || echo 'auth,authpriv.*                                /var/log/secure' >> "$f"
    grep -Eq 'mail\.\*' "$f" || echo 'mail.*                                          /var/log/maillog' >> "$f"
    grep -Eq 'cron\.\*' "$f" || echo 'cron.*                                          /var/log/cron' >> "$f"
    grep -Eq '\*\.emerg' "$f" || echo '*.emerg                                         *' >> "$f"
  fi

  systemctl enable --now rsyslog 2>/dev/null
  systemctl restart rsyslog 2>/dev/null
}

fix_U67() {
  local code="U-67"
  local autofix_flag="$(get_item_autofix "$code")"

  [ "$autofix_flag" != "1" ] && return 0

  find /var/log -maxdepth 1 -type f -exec chown root {} \; 2>/dev/null
  find /var/log -maxdepth 1 -type f -exec chmod 644 {} \; 2>/dev/null
}
