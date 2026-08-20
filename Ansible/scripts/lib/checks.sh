#!/bin/bash
# checks.sh - U-01~U-67 진단(check) 함수. common.sh 로드 후 사용.
# 각 함수는 json_result 한 줄을 stdout에 출력한다.

# ===== 계정 관리 (U-01~U-17) =====

check_U01() {
  local f="/etc/ssh/sshd_config" val status
  val=$(grep -Ei '^\s*PermitRootLogin' "$f" 2>/dev/null | tail -1 | awk '{print $2}')
  val=${val:-yes}
  status="FAIL"; [[ "$val" == "no" ]] && status="GOOD"
  json_result "U-01" "$status" "PermitRootLogin $val" "PermitRootLogin no"
}

check_U02() {
  local f="/etc/login.defs" maxd minlen status current
  maxd=$(awk '/^PASS_MAX_DAYS/{print $2}' "$f" 2>/dev/null)
  minlen=$(grep -Po '(?<=minlen=)[0-9]+' /etc/security/pwquality.conf 2>/dev/null | tail -1)
  maxd=${maxd:-99999}; minlen=${minlen:-0}
  current="PASS_MAX_DAYS=$maxd, pwquality.minlen=$minlen"
  status="FAIL"
  [ "$maxd" -le 90 ] 2>/dev/null && [ "$minlen" -ge 8 ] 2>/dev/null && status="GOOD"
  json_result "U-02" "$status" "$current" "PASS_MAX_DAYS<=90, minlen>=8"
}

check_U03() {
  local f="/etc/security/faillock.conf" deny status
  deny=$(grep -Po '(?<=^deny = )[0-9]+' "$f" 2>/dev/null)
  deny=${deny:-0}
  status="FAIL"
  [ "$deny" -ge 1 ] 2>/dev/null && [ "$deny" -le 5 ] 2>/dev/null && status="GOOD"
  json_result "U-03" "$status" "deny=$deny" "deny 1~5"
}

check_U04() {
  local status current
  if [ -f /etc/shadow ] && awk -F: '$2=="x"{c++} END{exit !c}' /etc/passwd; then
    status="GOOD"; current="shadow 사용, passwd 2필드=x"
  else
    status="FAIL"; current="passwd에 암호 해시 노출 가능"
  fi
  json_result "U-04" "$status" "$current" "/etc/shadow 사용"
}

check_U05() {
  local list status
  list=$(awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd | paste -sd, -)
  status="GOOD"; [ -n "$list" ] && status="FAIL"
  json_result "U-05" "$status" "UID0_accounts=[${list}]" "root만 UID 0"
}

check_U06() {
  local status current
  if grep -Eq '^\s*auth\s+required\s+pam_wheel\.so' /etc/pam.d/su 2>/dev/null; then
    status="GOOD"; current="pam_wheel.so 적용됨"
  else
    status="FAIL"; current="pam_wheel.so 미설정"
  fi
  json_result "U-06" "$status" "$current" "wheel 그룹만 su 허용"
}

check_U07() {
  local list
  list=$(awk -F: '($7 !~ /nologin|false/) && $3>=1000 {print $1}' /etc/passwd | paste -sd, -)
  json_result "U-07" "CHECK" "로그인가능 계정=[${list}]" "불필요 계정 없음(수동 확인 필요)"
}

check_U08() {
  local members cnt
  members=$(getent group wheel | awk -F: '{print $4}')
  cnt=$(echo "$members" | tr ',' '\n' | grep -c .)
  json_result "U-08" "CHECK" "wheel_members=[${members}](${cnt}명)" "관리자 최소 인원(수동 확인 필요)"
}

check_U09() {
  local bad
  bad=$(awk -F: '{print $4}' /etc/passwd | sort -u | while read -r g; do getent group "$g" >/dev/null || echo "$g"; done | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="FAIL"
  json_result "U-09" "$status" "no_such_gid=[${bad}]" "모든 GID가 존재해야 함"
}

check_U10() {
  local dup
  dup=$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d | paste -sd, -)
  status="GOOD"; [ -n "$dup" ] && status="FAIL"
  json_result "U-10" "$status" "dup_uid=[${dup}]" "UID 중복 없음"
}

check_U11() {
  local list
  list=$(awk -F: '$3>=1000 && $3!=65534 {print $1":"$7}' /etc/passwd | paste -sd, -)
  json_result "U-11" "CHECK" "user_shells=[${list}]" "불필요 계정은 nologin(수동 확인 필요)"
}

check_U12() {
  local tmout status
  tmout=$(grep -REo 'TMOUT=[0-9]+' /etc/profile /etc/profile.d/*.sh 2>/dev/null | head -1 | grep -Eo '[0-9]+$')
  tmout=${tmout:-0}
  status="FAIL"
  [ "$tmout" -gt 0 ] 2>/dev/null && [ "$tmout" -le 600 ] 2>/dev/null && status="GOOD"
  json_result "U-12" "$status" "TMOUT=$tmout" "TMOUT 1~600초"
}

check_U13() {
  local method status
  method=$(awk -F= '/^ENCRYPT_METHOD/{print $2}' /etc/login.defs 2>/dev/null | tr -d ' ')
  status="FAIL"; [[ "$method" == "SHA512" ]] && status="GOOD"
  json_result "U-13" "$status" "ENCRYPT_METHOD=${method:-미설정}" "ENCRYPT_METHOD SHA512"
}

check_U14() {
  local perm status
  perm=$(perm_octal /root)
  status="FAIL"
  perm_le "$perm" 750 && ! echo "$PATH" | grep -q '(^|:)\.(:|$)' && status="GOOD"
  json_result "U-14" "$status" "/root perm=$perm, PATH=$PATH" "/root<=750, PATH에 '.' 미포함"
}

check_U15() {
  local n
  n=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | wc -l)
  status="GOOD"; [ "$n" -gt 0 ] && status="CHECK"
  json_result "U-15" "$status" "소유자없는파일 ${n}개" "소유자/그룹 미존재 파일 없음"
}

check_U16() {
  local f="/etc/passwd" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="FAIL"
  [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  json_result "U-16" "$status" "owner=$own,perm=$perm" "root:root, 644 이하"
}

check_U17() {
  local bad
  bad=$(find /etc/rc.d/init.d /usr/lib/systemd/system -maxdepth 1 -type f ! -user root -perm /go+w 2>/dev/null | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="FAIL"
  json_result "U-17" "$status" "위험파일=[${bad}]" "시작스크립트 root 소유, 그룹/기타 쓰기금지"
}

# ===== 파일 및 디렉터리 관리 (U-18~U-33) =====

check_U18() {
  local f="/etc/shadow" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="FAIL"
  [ "$own" == "root" ] && perm_le "$perm" 400 && status="GOOD"
  json_result "U-18" "$status" "owner=$own,perm=$perm" "root:root, 400 이하"
}

check_U19() {
  local f="/etc/hosts" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="FAIL"
  [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  json_result "U-19" "$status" "owner=$own,perm=$perm" "root:root, 644 이하"
}

check_U20() {
  local f status="NA" current="파일 없음(N/A)"
  for f in /etc/xinetd.conf /etc/inetd.conf; do
    [ -f "$f" ] || continue
    local perm own; perm=$(perm_octal "$f"); own=$(owner_of "$f")
    current="$f owner=$own,perm=$perm"
    status="FAIL"; [ "$own" == "root" ] && perm_le "$perm" 600 && status="GOOD"
  done
  json_result "U-20" "$status" "$current" "root:root, 600 이하"
}

check_U21() {
  local f status="NA" current="파일 없음(N/A)"
  for f in /etc/rsyslog.conf /etc/syslog.conf; do
    [ -f "$f" ] || continue
    local perm own; perm=$(perm_octal "$f"); own=$(owner_of "$f")
    current="$f owner=$own,perm=$perm"
    status="FAIL"; [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  done
  json_result "U-21" "$status" "$current" "root:root, 644 이하"
}

check_U22() {
  local f="/etc/services" perm own status
  perm=$(perm_octal "$f"); own=$(owner_of "$f")
  status="FAIL"
  [ "$own" == "root" ] && perm_le "$perm" 644 && status="GOOD"
  json_result "U-22" "$status" "owner=$own,perm=$perm" "root:root, 644 이하"
}

check_U23() {
  local n
  n=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | wc -l)
  json_result "U-23" "CHECK" "SUID/SGID 파일 ${n}개" "불필요 SUID/SGID 제거(수동 확인 필요)"
}

check_U24() {
  local bad
  bad=$(find /etc/profile /etc/bashrc /etc/profile.d -type f ! -user root -o -type f -perm /o+w 2>/dev/null | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="FAIL"
  json_result "U-24" "$status" "위험파일=[${bad}]" "root 소유, 타 사용자 쓰기 금지"
}

check_U25() {
  local n
  n=$(find / -xdev -type f -perm -0002 -not -path '/proc/*' -not -path '/tmp/*' -not -path '/var/tmp/*' -not -path '/dev/shm/*' 2>/dev/null | wc -l)
  status="GOOD"; [ "$n" -gt 0 ] && status="CHECK"
  json_result "U-25" "$status" "world_writable ${n}개" "world writable 파일 없음"
}

check_U26() {
  local n
  n=$(find /dev -xdev -type f 2>/dev/null | wc -l)
  status="GOOD"; [ "$n" -gt 0 ] && status="CHECK"
  json_result "U-26" "$status" "/dev 일반파일 ${n}개" "device 파일만 존재"
}

check_U27() {
  local n
  n=$(find /root /home -maxdepth 2 \( -name .rhosts -o -name hosts.equiv \) 2>/dev/null | wc -l)
  n=$((n + $( [ -f /etc/hosts.equiv ] && echo 1 || echo 0 )))
  status="GOOD"; [ "$n" -gt 0 ] && status="FAIL"
  json_result "U-27" "$status" ".rhosts/hosts.equiv ${n}개" "사용 금지(파일 없음/000)"
}

check_U28() {
  local active
  active=$(firewall-cmd --state 2>/dev/null)
  json_result "U-28" "CHECK" "firewalld=${active:-미확인}" "필요 IP/포트만 허용(수동 정책 확인 필요)"
}

check_U29() {
  local f="/etc/hosts.lpd" status="NA" current="파일 없음(N/A)"
  if [ -f "$f" ]; then
    local perm own; perm=$(perm_octal "$f"); own=$(owner_of "$f")
    current="owner=$own,perm=$perm"
    status="FAIL"; [ "$own" == "root" ] && perm_le "$perm" 600 && status="GOOD"
  fi
  json_result "U-29" "$status" "$current" "root:root, 600 이하"
}

check_U30() {
  local u status
  u=$(grep -REo 'umask [0-9]+' /etc/profile /etc/bashrc 2>/dev/null | head -1 | awk '{print $2}')
  u=${u:-000}
  status="FAIL"
  [ "$u" -ge 022 ] 2>/dev/null && status="GOOD"
  json_result "U-30" "$status" "umask=$u" "umask 022 이상"
}

check_U31() {
  local bad
  bad=$(awk -F: '$3>=1000 && $3!=65534 {print $6}' /etc/passwd | while read -r d; do
    [ -d "$d" ] || continue
    p=$(stat -c '%a' "$d"); [ "$p" -gt 750 ] 2>/dev/null && echo "$d:$p"
  done | paste -sd, -)
  status="GOOD"; [ -n "$bad" ] && status="FAIL"
  json_result "U-31" "$status" "위반=[${bad}]" "홈 디렉토리 750 이하, 본인 소유"
}

check_U32() {
  local bad
  bad=$(awk -F: '$3>=1000 && $3!=65534 {print $1":"$6}' /etc/passwd | while IFS=: read -r u d; do
    [ -d "$d" ] || echo "$u:$d"
  done | paste -sd, -)
  json_result "U-32" "CHECK" "홈디렉토리없음=[${bad}]" "지정된 홈 디렉토리가 실존해야 함"
}

check_U33() {
  local n
  n=$(find / -xdev -name '.*' -type f 2>/dev/null | wc -l)
  json_result "U-33" "CHECK" "숨김파일 ${n}개" "불필요 숨김파일/디렉토리 제거(수동 확인)"
}

# ===== 서비스 관리 (U-34~U-63) =====

check_svc_simple() {
  local id="$1" svc="$2" expected="$3"
  local res status current
  res=$(svc_disabled_or_absent "$svc")
  status="${res%%:*}"; current="${res#*:}"
  json_result "$id" "$status" "$svc=$current" "$expected"
}

check_U34() { check_svc_simple "U-34" "finger" "비활성화"; }
check_U35() {
  local val status
  val=$(grep -Ei '^\s*anonymous_enable' /etc/vsftpd/vsftpd.conf 2>/dev/null | tail -1 | awk -F= '{print $2}' | tr -d ' ')
  if [ ! -f /etc/vsftpd/vsftpd.conf ]; then status="NA"; val="not_installed"
  else status="FAIL"; [[ "${val,,}" == "no" ]] && status="GOOD"; fi
  json_result "U-35" "$status" "anonymous_enable=$val" "익명 접근 금지(NO)"
}
check_U36() {
  local n
  n=0
  for s in rsh rlogin rexec; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="FAIL"
  json_result "U-36" "$status" "active_r_services=$n" "rsh/rlogin/rexec 비활성화"
}
check_U37() {
  local f="/etc/crontab" perm status="NA" current="파일 없음"
  if [ -f "$f" ]; then
    perm=$(perm_octal "$f"); current="perm=$perm"
    status="FAIL"; perm_le "$perm" 640 && status="GOOD"
  fi
  json_result "U-37" "$status" "$current" "/etc/crontab 640 이하"
}
check_U38() {
  local n=0
  for s in echo discard daytime chargen; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="FAIL"
  json_result "U-38" "$status" "active_dos_services=$n" "echo/discard/daytime/chargen 비활성화"
}
check_U39() { check_svc_simple "U-39" "nfs-server" "미사용시 비활성화"; }
check_U40() {
  local f="/etc/exports" current="파일 없음(N/A)" status="NA"
  if [ -f "$f" ]; then current=$(grep -v '^#' "$f" | grep -c .); status="CHECK"; fi
  json_result "U-40" "$status" "exports_entries=$current" "everyone(*) 접근 금지(수동 확인)"
}
check_U41() { check_svc_simple "U-41" "autofs" "미사용시 비활성화"; }
check_U42() { check_svc_simple "U-42" "rpcbind" "미사용시 비활성화"; }
check_U43() {
  local n=0
  for s in ypserv ypbind; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="FAIL"
  json_result "U-43" "$status" "active_nis_services=$n" "NIS/NIS+ 비활성화"
}
check_U44() {
  local n=0
  for s in tftp talk ntalk; do svc_exists "$s" && (svc_active "$s" || svc_enabled "$s") && n=$((n+1)); done
  status="GOOD"; [ "$n" -gt 0 ] && status="FAIL"
  json_result "U-44" "$status" "active_services=$n" "tftp/talk 비활성화"
}
check_U45() {
  local ver="not_installed"
  command -v postconf &>/dev/null && ver=$(postconf mail_version 2>/dev/null)
  json_result "U-45" "CHECK" "mail_version=$ver" "최신 패치 버전 사용(수동 확인)"
}
check_U46() {
  local status="NA" current="postfix 미설치(N/A)"
  if command -v postconf &>/dev/null; then
    local restrict; restrict=$(postconf -h smtpd_client_restrictions 2>/dev/null)
    current="smtpd_client_restrictions=$restrict"
    status="CHECK"
  fi
  json_result "U-46" "$status" "$current" "일반 사용자 메일 릴레이 제한(수동 확인)"
}
check_U47() {
  local status="NA" current="postfix 미설치(N/A)"
  command -v postconf &>/dev/null && { current="smtpd_relay_restrictions=$(postconf -h smtpd_relay_restrictions 2>/dev/null)"; status="CHECK"; }
  json_result "U-47" "$status" "$current" "오픈 릴레이 금지(수동 확인)"
}
# 코드 수정 - 0819 정진우
check_U48() {
  local code="U-48"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/postfix/main.cf"
  local cmd="postconf -h disable_vrfy_command 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if command -v postconf >/dev/null 2>&1; then
    local v
    v=$(postconf -h disable_vrfy_command 2>/dev/null)
    cmd_out="disable_vrfy_command=$v"

    if [ "$v" = "yes" ]; then
      status="양호"
      evidence="SMTP 서비스의 vrfy 명령어가 제한되어 있습니다 (disable_vrfy_command=yes)."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      evidence="SMTP 서비스의 vrfy 명령어가 제한되어 있지 않습니다."
      rec="main.cf 파일에서 disable_vrfy_command = yes 로 설정하세요."
      rem_cmd="postconf -e 'disable_vrfy_command = yes' && systemctl reload postfix"
    fi
  else
    status="N/A"
    cmd_out="postfix 미설치"
    evidence="SMTP 서비스(postfix)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U49() {
  local code="U-49"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="DNS 서비스"
  local cmd="named -v 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if command -v named >/dev/null 2>&1; then
    cmd_out=$(named -v 2>/dev/null)
    status="검토"
    evidence="DNS 서비스가 설치되어 있습니다. 출력된 버전이 최신 패치 버전인지 수동으로 확인해야 합니다."
    rec="취약점이 없는 최신 버전의 DNS(BIND) 데몬으로 업데이트하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="named 미설치"
    evidence="DNS 서비스(named)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U50() {
  local code="U-50"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/named.conf"
  local cmd="cat /etc/named.conf | grep allow-transfer"
  
  local cmd_out status evidence rec rem_cmd

  if command -v named >/dev/null 2>&1; then
    cmd_out="named.conf allow-transfer 확인 필요"
    status="검토"
    evidence="DNS 서비스가 실행 중입니다. allow-transfer 설정이 인가된 IP로 제한되어 있는지 수동 확인이 필요합니다."
    rec="named.conf 파일의 options 또는 zone 구문에서 allow-transfer { 허용IP; }; 형태로 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="named 미설치"
    evidence="DNS 서비스(named)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U51() {
  local code="U-51"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/named.conf"
  local cmd="cat /etc/named.conf | grep allow-update"
  
  local cmd_out status evidence rec rem_cmd

  if command -v named >/dev/null 2>&1; then
    cmd_out="named.conf allow-update 확인 필요"
    status="검토"
    evidence="DNS 서비스가 실행 중입니다. 동적 업데이트(allow-update)가 제한되어 있는지 수동 확인이 필요합니다."
    rec="동적 업데이트가 불필요한 경우 allow-update { none; }; 으로 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="named 미설치"
    evidence="DNS 서비스(named)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U52() {
  local code="U-52"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="telnet.socket"
  local cmd="systemctl is-active telnet.socket"
  
  local cmd_out status evidence rec rem_cmd
  local is_active

  is_active=$(systemctl is-active telnet.socket 2>/dev/null)
  cmd_out="telnet.socket active status: ${is_active:-unknown}"

  if [ "$is_active" = "active" ]; then
    status="취약"
    evidence="보안이 취약한 Telnet 서비스가 활성화되어 있습니다."
    rec="Telnet 서비스를 비활성화하고 SSH를 사용하세요."
    rem_cmd="systemctl stop telnet.socket && systemctl disable telnet.socket"
  else
    status="양호"
    evidence="Telnet 서비스가 비활성화되어 있거나 설치되어 있지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U53() {
  local code="U-53"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/vsftpd/vsftpd.conf"
  local cmd="grep -Ei '^\s*ftpd_banner' /etc/vsftpd/vsftpd.conf 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if [ -f "$target_file" ]; then
    local banner
    banner=$(grep -Ei '^\s*ftpd_banner' "$target_file" | tail -1)
    
    if [ -n "$banner" ]; then
      cmd_out="$banner"
      status="양호"
      evidence="FTP 서비스 설정 파일에 배너(ftpd_banner)가 설정되어 있어 버전 정보 노출이 제한됩니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      cmd_out="ftpd_banner 미설정"
      status="취약"
      evidence="FTP 서비스 설정 파일에 배너가 설정되어 있지 않아 접속 시 버전 정보가 노출될 수 있습니다."
      rec="vsftpd.conf 파일에 ftpd_banner 옵션을 추가하여 경고 메시지를 설정하세요."
      rem_cmd="echo 'ftpd_banner=Authorized users only.' >> /etc/vsftpd/vsftpd.conf && systemctl restart vsftpd"
    fi
  else
    status="N/A"
    cmd_out="vsftpd 미설치"
    evidence="FTP 서비스(vsftpd) 설정 파일이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U54() {
  local code="U-54"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="vsftpd 서비스"
  local cmd="systemctl is-active vsftpd"
  
  local cmd_out status evidence rec rem_cmd
  local is_active

  is_active=$(systemctl is-active vsftpd 2>/dev/null)
  cmd_out="vsftpd active status: ${is_active:-unknown}"

  if [ "$is_active" = "active" ]; then
    status="검토"
    evidence="FTP 서비스가 활성화되어 있습니다. 서비스 사용 목적 및 SFTP 대체 가능 여부를 수동으로 판단해야 합니다."
    rec="미사용 시 FTP 서비스를 비활성화하고, 필요시 SFTP를 사용하세요."
    rem_cmd="systemctl stop vsftpd && systemctl disable vsftpd"
  else
    status="양호"
    evidence="FTP 서비스가 비활성화되어 있거나 설치되어 있지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U55() {
  local code="U-55"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/passwd"
  local cmd="getent passwd ftp"
  
  local cmd_out status evidence rec rem_cmd shell

  shell=$(getent passwd ftp | awk -F: '{print $7}')
  
  if [ -z "$shell" ]; then
    status="N/A"
    cmd_out="계정없음"
    evidence="시스템에 ftp 계정이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  else
    cmd_out="ftp_shell=$shell"
    if [[ "$shell" == *nologin* || "$shell" == *false* ]]; then
      status="양호"
      evidence="ftp 계정에 nologin 쉘이 부여되어 직접 로그인이 불가능합니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      evidence="ftp 계정에 로그인 가능한 쉘이 부여되어 있습니다."
      rec="ftp 계정의 쉘을 /usr/sbin/nologin 또는 /bin/false 로 변경하세요."
      rem_cmd="usermod -s /usr/sbin/nologin ftp"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U56() {
  local code="U-56"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/vsftpd/vsftpd.conf, TCP Wrappers"
  local cmd="ls -l /etc/vsftpd/vsftpd.conf 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if [ -f /etc/vsftpd/vsftpd.conf ]; then
    status="검토"
    cmd_out="접근제어 확인 필요"
    evidence="FTP 서비스가 설치되어 있습니다. TCP Wrappers(/etc/hosts.allow, deny) 또는 user_list를 통한 접근 제어 설정 여부를 수동으로 확인해야 합니다."
    rec="인가된 IP 및 계정만 접속할 수 있도록 FTP 접근 제어를 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="vsftpd 미설치"
    evidence="FTP 서비스(vsftpd)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U57() {
  local code="U-57"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/vsftpd/ftpusers"
  local cmd="grep -qx root /etc/vsftpd/ftpusers 2>/dev/null || grep -qx root /etc/ftpusers 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local f file_found=0 root_blocked=0

  for f in /etc/ftpusers /etc/vsftpd/ftpusers; do
    if [ -f "$f" ]; then
      file_found=1
      if grep -qx root "$f"; then
        root_blocked=1
        cmd_out="root in $f"
        break
      fi
    fi
  done

  if [ "$file_found" -eq 0 ]; then
    status="N/A"
    cmd_out="파일 없음"
    evidence="FTP 접근 제어 파일(ftpusers)이 존재하지 않습니다 (FTP 미설정 환경일 가능성 높음)."
    rec="해당 없음"
    rem_cmd=""
  else
    if [ "$root_blocked" -eq 1 ]; then
      status="양호"
      evidence="ftpusers 파일에 root 계정이 등록되어 FTP 접속이 차단되어 있습니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      cmd_out="root not in ftpusers"
      evidence="ftpusers 파일에 root 계정이 등록되어 있지 않아 root 계정으로 FTP 접속이 가능합니다."
      rec="ftpusers 파일에 root 계정을 추가하여 접속을 차단하세요."
      rem_cmd="echo 'root' >> /etc/vsftpd/ftpusers"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U58() {
  local code="U-58"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="snmpd 서비스"
  local cmd="systemctl is-active snmpd"
  
  local cmd_out status evidence rec rem_cmd
  local is_active

  is_active=$(systemctl is-active snmpd 2>/dev/null)
  cmd_out="snmpd active status: ${is_active:-unknown}"

  if [ "$is_active" = "active" ]; then
    status="검토"
    evidence="SNMP 서비스(snmpd)가 활성화되어 있습니다. 사용 목적이 명확한지 수동으로 확인이 필요합니다."
    rec="불필요한 경우 SNMP 서비스를 비활성화하세요."
    rem_cmd="systemctl stop snmpd && systemctl disable snmpd"
  else
    status="양호"
    evidence="SNMP 서비스가 비활성화되어 있거나 설치되어 있지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U59() {
  local code="U-59"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/snmp/snmpd.conf"
  local cmd="cat /etc/snmp/snmpd.conf"
  
  local cmd_out status evidence rec rem_cmd

  if command -v snmpd >/dev/null 2>&1; then
    status="검토"
    cmd_out="SNMP 버전 확인 필요"
    evidence="SNMP 서비스가 설치되어 있습니다. SNMP 버전(v3 권장) 사용 여부를 수동으로 확인해야 합니다."
    rec="보안이 강화된 SNMPv3 버전을 사용하도록 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="snmpd 미설치"
    evidence="SNMP 서비스(snmpd)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U60() {
  local code="U-60"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/snmp/snmpd.conf"
  local cmd="grep -E 'rocommunity|rwcommunity' /etc/snmp/snmpd.conf 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if command -v snmpd >/dev/null 2>&1; then
    status="검토"
    cmd_out="community 문자열 확인 필요"
    evidence="SNMP 서비스가 설치되어 있습니다. Community 문자열이 public/private 등 기본값인지 수동으로 확인해야 합니다."
    rec="추측하기 어려운 복잡한 Community 문자열로 변경하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="snmpd 미설치"
    evidence="SNMP 서비스(snmpd)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U61() {
  local code="U-61"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/snmp/snmpd.conf"
  local cmd="cat /etc/snmp/snmpd.conf"
  
  local cmd_out status evidence rec rem_cmd

  if command -v snmpd >/dev/null 2>&1; then
    status="검토"
    cmd_out="snmpd.conf 접근제어 확인 필요"
    evidence="SNMP 서비스가 설치되어 있습니다. 허용된 IP만 접근할 수 있도록 ACL 설정이 되어 있는지 수동으로 확인해야 합니다."
    rec="snmpd.conf에서 rocommunity/rwcommunity 설정 시 접근 가능한 IP를 명시하여 제한하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="snmpd 미설치"
    evidence="SNMP 서비스(snmpd)가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U62() {
  local code="U-62"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/motd, /etc/issue, /etc/issue.net"
  local cmd="ls -s /etc/motd /etc/issue /etc/issue.net"
  
  local cmd_out status evidence rec rem_cmd
  local ok=1 f
  local empty_files=""

  for f in /etc/motd /etc/issue /etc/issue.net; do
    if [ ! -s "$f" ]; then
      ok=0
      empty_files="$empty_files $f"
    fi
  done

  cmd_out="motd/issue/issue.net 비어있는 파일:${empty_files:- 없음}"

  if [ "$ok" -eq 1 ]; then
    status="양호"
    evidence="모든 로그인 경고 배너 파일에 내용이 설정되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="로그인 경고 배너 파일(${empty_files# })의 내용이 비어 있습니다."
    rec="인가되지 않은 사용자의 시스템 접근을 경고하는 메시지를 해당 파일들에 추가하세요."
    rem_cmd="echo 'Authorized users only.' > /etc/motd && echo 'Authorized users only.' > /etc/issue && echo 'Authorized users only.' > /etc/issue.net"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U63() {
  local code="U-63"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/sudoers"
  local cmd="stat -c '%a' /etc/sudoers"
  
  local cmd_out status evidence rec rem_cmd perm

  if [ -f /etc/sudoers ]; then
    perm=$(stat -c '%a' /etc/sudoers 2>/dev/null)
    cmd_out="sudoers perm=${perm:-unknown}"
    status="검토"
    evidence="/etc/sudoers 파일의 권한이 ${perm}입니다. 권한이 440 이하인지, 그리고 최소 권한의 원칙에 따라 사용자 권한이 적절히 부여되어 있는지 수동으로 확인해야 합니다."
    rec="/etc/sudoers 권한을 440으로 설정하고, 불필요하게 부여된 권한(ALL=(ALL) ALL)을 최소화하세요."
    rem_cmd="chmod 440 /etc/sudoers"
  else
    status="N/A"
    cmd_out="sudoers 없음"
    evidence="/etc/sudoers 파일이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}


# ===== 패치 관리 (U-64) =====

check_U64() {
  local n
  n=$(dnf check-update --quiet 2>/dev/null | grep -c . )
  json_result "U-64" "CHECK" "적용가능업데이트 ${n}건" "정기 패치 적용(수동 확인)"
}

# ===== 로그 관리 (U-65~U-67) =====

check_U65() {
  local status="CHECK" current="chronyd 미설치(N/A)"
  svc_exists chronyd && current="chronyd active=$(svc_active chronyd && echo yes || echo no)"
  json_result "U-65" "$status" "$current" "NTP 동기화 구성(수동 확인)"
}
check_U66() {
  local status current
  if svc_active rsyslog; then status="GOOD"; current="rsyslog active"
  else status="FAIL"; current="rsyslog inactive"; fi
  json_result "U-66" "$status" "$current" "rsyslog 활성화 및 정책 로깅"
}
check_U67() {
  local d="/var/log" perm own status
  perm=$(perm_octal "$d"); own=$(owner_of "$d")
  status="FAIL"
  [ "$own" == "root" ] && perm_le "$perm" 750 && status="GOOD"
  json_result "U-67" "$status" "owner=$own,perm=$perm" "root 소유, 750 이하"
}
