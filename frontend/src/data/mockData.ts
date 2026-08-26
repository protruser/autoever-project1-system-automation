// ── Types matching the real scan JSON format ──────────────────────────────

export type Importance = "상" | "중" | "하";
export type CheckStatus = "양호" | "취약" | "N/A" | "수동";
// orange 추가 - 공식 5단계 등급표(우수/양호/보통/미흡/취약)의 "미흡" 단계 색상
export type GradeColor = "green" | "yellow" | "orange" | "red";
export type RemediationState = "pending" | "running" | "done" | "failed";

export interface ScanInfo {
  scan_id: string;
  project_name: string;
  scan_date: string;
  auditor: string;
}

export interface HostInfo {
  hostname: string;
  ip: string;
  os: string;
  kernel: string;
  arch: string;
}

export interface HostSummary {
  total: number;
  pass: number;
  vuln: number;
  na: number;
  manual: number;
  max_score: number;
  deducted_score: number;
  compliance_rate: string;
  security_score_100: number;
  security_score_ratio: number;
  grade: string;
  grade_color: GradeColor;
}

export interface CheckResult {
  code: string;
  category: string;
  title: string;
  importance: Importance;
  status: CheckStatus;
  target_file: string;
  command: string;
  command_output: string;
  evidence_description: string;
  recommendation_text: string;
  remediation_cmd: string;
  weight_score: number;
  risk_score: number;
  // UI-only state (not in JSON)
  remediation_state?: RemediationState;
  selected?: boolean;
}

export interface ScanHost {
  host_info: HostInfo;
  summary: HostSummary;
  results: CheckResult[];
}

export interface TotalSummary {
  total_hosts: number;
  total_checks: number;
  total_pass: number;
  total_vuln: number;
  total_na: number;
  average_compliance_rate: string;
  average_security_score: number;
  average_security_ratio: number;
  total_grade: string;
  total_grade_color: GradeColor;
}

export interface ScanReport {
  scan_info: ScanInfo;
  total_summary: TotalSummary;
  hosts: ScanHost[];
}

// ── Server registry (separate from scan results) ──────────────────────────

export type ServerStatus = "online" | "offline" | "scanning" | "error";

export interface Server {
  id: string;
  hostname: string;
  ip: string;
  os: string;
  group: string;
  status: ServerStatus;
  lastScan: string | null;
  lastScanId: string | null;
}

// ── Mock check results ─────────────────────────────────────────────────────

const CHECKS_HOST1: CheckResult[] = [
  {
    code: "U-01", category: "계정 관리", title: "root 계정 원격 접속 제한",
    importance: "상", status: "취약",
    target_file: "/etc/ssh/sshd_config",
    command: "grep -Ei '^\\s*PermitRootLogin' /etc/ssh/sshd_config",
    command_output: "PermitRootLogin yes",
    evidence_description: "sshd_config의 PermitRootLogin 값이 'yes'로 되어 있어 root 계정의 원격 SSH 접속이 허용됩니다.",
    recommendation_text: "sshd_config에서 PermitRootLogin을 no로 변경한 뒤 SSH 서비스를 재시작하세요.",
    remediation_cmd: "sed -i -E 's/^\\s*#?\\s*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart ssh",
    weight_score: 3, risk_score: 3,
  },
  {
    code: "U-02", category: "계정 관리", title: "패스워드 복잡성 설정",
    importance: "상", status: "취약",
    target_file: "/etc/security/pwquality.conf",
    command: "grep -E 'minlen|dcredit|ucredit|lcredit|ocredit' /etc/security/pwquality.conf",
    command_output: "# minlen = 8\n# dcredit = 0",
    evidence_description: "pwquality.conf에서 minlen 및 복잡성 옵션이 주석 처리되어 있어 패스워드 복잡성 정책이 미적용 상태입니다.",
    recommendation_text: "minlen=8, dcredit=-1, ucredit=-1, lcredit=-1, ocredit=-1 설정을 주석 해제하거나 추가하세요.",
    remediation_cmd: "sed -i 's/^# *minlen.*/minlen = 8/' /etc/security/pwquality.conf && sed -i 's/^# *dcredit.*/dcredit = -1/' /etc/security/pwquality.conf",
    weight_score: 3, risk_score: 3,
  },
  {
    code: "U-03", category: "계정 관리", title: "계정 잠금 임계값 설정",
    importance: "상", status: "취약",
    target_file: "/etc/pam.d/common-auth",
    command: "grep 'pam_tally2\\|pam_faillock' /etc/pam.d/common-auth",
    command_output: "",
    evidence_description: "pam_faillock 또는 pam_tally2 모듈 설정이 존재하지 않아 로그인 실패 횟수 제한이 없습니다.",
    recommendation_text: "pam_faillock 모듈을 추가하여 deny=5, unlock_time=300을 설정하세요.",
    remediation_cmd: "echo 'auth required pam_faillock.so preauth silent deny=5 unlock_time=300' >> /etc/pam.d/common-auth",
    weight_score: 2, risk_score: 2,
  },
  {
    code: "U-04", category: "계정 관리", title: "패스워드 최대 사용기간 설정",
    importance: "중", status: "취약",
    target_file: "/etc/login.defs",
    command: "grep PASS_MAX_DAYS /etc/login.defs",
    command_output: "PASS_MAX_DAYS   99999",
    evidence_description: "PASS_MAX_DAYS 값이 99999로 설정되어 패스워드 만료 기간이 사실상 무제한입니다.",
    recommendation_text: "PASS_MAX_DAYS를 90 이하로 변경하세요.",
    remediation_cmd: "sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs",
    weight_score: 2, risk_score: 2,
  },
  {
    code: "U-05", category: "계정 관리", title: "패스워드 최소 사용기간 설정",
    importance: "하", status: "양호",
    target_file: "/etc/login.defs",
    command: "grep PASS_MIN_DAYS /etc/login.defs",
    command_output: "PASS_MIN_DAYS   1",
    evidence_description: "PASS_MIN_DAYS 값이 1로 설정되어 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 1, risk_score: 0,
  },
  {
    code: "U-06", category: "계정 관리", title: "불필요한 계정 제거",
    importance: "중", status: "취약",
    target_file: "/etc/passwd",
    command: "awk -F: '$7 != \"/sbin/nologin\" && $7 != \"/usr/sbin/nologin\" && $7 != \"/bin/false\" && $1 != \"root\" && $1 != \"sync\" && $1 != \"shutdown\" && $1 != \"halt\" {print $1}' /etc/passwd",
    command_output: "games\nnews\noperator\nftp",
    evidence_description: "서비스에 사용되지 않는 기본 계정(games, news, operator, ftp)이 존재합니다.",
    recommendation_text: "userdel 명령으로 불필요한 계정을 삭제하세요.",
    remediation_cmd: "for u in games news operator ftp; do userdel -r $u 2>/dev/null; done",
    weight_score: 2, risk_score: 2,
  },
  {
    code: "U-07", category: "계정 관리", title: "관리자 그룹 최소화",
    importance: "중", status: "양호",
    target_file: "/etc/group",
    command: "grep '^sudo:' /etc/group",
    command_output: "sudo:x:27:ubuntu",
    evidence_description: "sudo 그룹에 ubuntu 계정만 포함되어 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 2, risk_score: 0,
  },
  {
    code: "U-08", category: "파일 및 디렉터리 관리", title: "/etc/passwd 파일 소유자 및 권한 설정",
    importance: "상", status: "양호",
    target_file: "/etc/passwd",
    command: "stat -c '%a %U' /etc/passwd",
    command_output: "644 root",
    evidence_description: "/etc/passwd 파일의 권한이 644이고 소유자가 root로 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 3, risk_score: 0,
  },
  {
    code: "U-09", category: "파일 및 디렉터리 관리", title: "/etc/shadow 파일 소유자 및 권한 설정",
    importance: "상", status: "양호",
    target_file: "/etc/shadow",
    command: "stat -c '%a %U' /etc/shadow",
    command_output: "640 root",
    evidence_description: "/etc/shadow 파일의 권한이 640이고 소유자가 root로 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 3, risk_score: 0,
  },
  {
    code: "U-10", category: "파일 및 디렉터리 관리", title: "/etc/hosts 파일 소유자 및 권한 설정",
    importance: "하", status: "양호",
    target_file: "/etc/hosts",
    command: "stat -c '%a %U' /etc/hosts",
    command_output: "644 root",
    evidence_description: "/etc/hosts 파일의 권한이 644이고 소유자가 root로 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 1, risk_score: 0,
  },
  {
    code: "U-11", category: "파일 및 디렉터리 관리", title: "SUID/SGID 설정 파일 점검",
    importance: "상", status: "N/A",
    target_file: "/",
    command: "find / -xdev \\( -perm -4000 -o -perm -2000 \\) -type f 2>/dev/null",
    command_output: "/usr/bin/sudo\n/usr/bin/passwd\n/usr/bin/chsh\n/usr/local/bin/custom_backup",
    evidence_description: "표준 SUID 파일 외에 /usr/local/bin/custom_backup 파일에 비표준 SUID 비트가 설정되어 있습니다.",
    recommendation_text: "비표준 SUID 파일의 필요성을 검토하고 불필요한 경우 SUID 비트를 제거하세요.",
    remediation_cmd: "chmod u-s /usr/local/bin/custom_backup",
    weight_score: 3, risk_score: 0,
  },
  {
    code: "U-12", category: "파일 및 디렉터리 관리", title: "world-writable 파일 점검",
    importance: "상", status: "취약",
    target_file: "/",
    command: "find / -xdev -type f -perm -0002 2>/dev/null | grep -v '/proc' | head -10",
    command_output: "/tmp/app_socket\n/var/log/custom_app.log\n/opt/webapp/uploads/temp",
    evidence_description: "일반 사용자가 쓰기 가능한 파일 3개가 발견되었습니다.",
    recommendation_text: "chmod o-w 명령으로 타인 쓰기 권한을 제거하세요.",
    remediation_cmd: "find / -xdev -type f -perm -0002 2>/dev/null | grep -v '/proc' | xargs chmod o-w 2>/dev/null",
    weight_score: 3, risk_score: 3,
  },
  {
    code: "U-13", category: "서비스 관리", title: "불필요한 서비스 비활성화 (telnet)",
    importance: "상", status: "양호",
    target_file: "/etc/inetd.conf",
    command: "systemctl is-active telnet 2>/dev/null; ss -tlnp | grep ':23'",
    command_output: "inactive",
    evidence_description: "telnet 서비스가 비활성화 상태입니다. 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 3, risk_score: 0,
  },
  {
    code: "U-14", category: "서비스 관리", title: "불필요한 서비스 비활성화 (FTP)",
    importance: "상", status: "양호",
    target_file: "/etc/vsftpd.conf",
    command: "systemctl is-active vsftpd 2>/dev/null; ss -tlnp | grep ':21'",
    command_output: "inactive",
    evidence_description: "FTP 서비스가 비활성화 상태입니다. 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 3, risk_score: 0,
  },
  {
    code: "U-15", category: "서비스 관리", title: "NFS 보안 설정",
    importance: "중", status: "양호",
    target_file: "/etc/exports",
    command: "systemctl is-active nfs-server 2>/dev/null",
    command_output: "inactive",
    evidence_description: "NFS 서비스가 비활성화되어 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 2, risk_score: 0,
  },
  {
    code: "U-16", category: "서비스 관리", title: "automountd 서비스 비활성화",
    importance: "하", status: "양호",
    target_file: "",
    command: "systemctl is-active autofs 2>/dev/null",
    command_output: "inactive",
    evidence_description: "autofs 서비스가 비활성화되어 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 1, risk_score: 0,
  },
  {
    code: "U-17", category: "패치 관리", title: "최신 보안 패치 적용",
    importance: "상", status: "취약",
    target_file: "",
    command: "apt list --upgradable 2>/dev/null | grep -i security | wc -l",
    command_output: "23",
    evidence_description: "보안 업데이트 미적용 패키지가 23개 존재합니다. (openssl, libssl, linux-image 등 포함)",
    recommendation_text: "apt-get update && apt-get upgrade -y 명령으로 보안 패치를 적용하세요.",
    remediation_cmd: "apt-get update && apt-get upgrade -y",
    weight_score: 3, risk_score: 3,
  },
  {
    code: "U-18", category: "로그 관리", title: "로그 파일 권한 설정",
    importance: "중", status: "취약",
    target_file: "/var/log",
    command: "find /var/log -type f -perm /o+r 2>/dev/null | head -5",
    command_output: "/var/log/auth.log\n/var/log/syslog",
    evidence_description: "/var/log/auth.log, /var/log/syslog 등의 로그 파일에 타인 읽기 권한이 설정되어 있습니다.",
    recommendation_text: "주요 로그 파일의 권한을 640 이하로 변경하세요.",
    remediation_cmd: "chmod 640 /var/log/auth.log /var/log/syslog",
    weight_score: 2, risk_score: 2,
  },
  {
    code: "U-19", category: "로그 관리", title: "원격 로그 서버 설정",
    importance: "중", status: "양호",
    target_file: "/etc/rsyslog.conf",
    command: "grep -E '^[^#]*@@?' /etc/rsyslog.conf",
    command_output: "*.* @@192.168.1.200:514",
    evidence_description: "rsyslog가 원격 로그 서버(192.168.1.200:514)로 로그를 전송하고 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 2, risk_score: 0,
  },
  {
    code: "U-20", category: "네트워크 서비스", title: "SSH 프로토콜 버전 설정",
    importance: "상", status: "양호",
    target_file: "/etc/ssh/sshd_config",
    command: "grep -i '^Protocol' /etc/ssh/sshd_config; ssh -V 2>&1 | head -1",
    command_output: "OpenSSH_8.9p1 Ubuntu-3ubuntu0.6, OpenSSL 3.0.2",
    evidence_description: "OpenSSH 8.9p1로 SSHv2만 지원하며 SSHv1은 기본적으로 비활성화되어 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 3, risk_score: 0,
  },
  {
    code: "U-21", category: "네트워크 서비스", title: "SSH 접속 허용 IP 설정",
    importance: "중", status: "N/A",
    target_file: "/etc/hosts.allow",
    command: "grep -i 'sshd\\|ssh' /etc/hosts.allow 2>/dev/null",
    command_output: "",
    evidence_description: "/etc/hosts.allow에 SSH 접속 허용 IP가 설정되어 있지 않으나, 방화벽(ufw)에서 별도 제어 중입니다.",
    recommendation_text: "hosts.allow 또는 ufw로 SSH 접속 IP를 제한하세요.",
    remediation_cmd: "echo 'sshd: 10.8.0.0/24' >> /etc/hosts.allow && echo 'sshd: ALL' >> /etc/hosts.deny",
    weight_score: 2, risk_score: 0,
  },
  {
    code: "U-22", category: "네트워크 서비스", title: "방화벽 설정",
    importance: "상", status: "양호",
    target_file: "",
    command: "ufw status verbose 2>/dev/null | head -10",
    command_output: "Status: active\nTo                         Action      From\n22/tcp                     ALLOW IN    10.8.0.0/24\n80/tcp                     ALLOW IN    Anywhere\n443/tcp                    ALLOW IN    Anywhere",
    evidence_description: "ufw가 활성화되어 있으며 SSH는 내부망(10.8.0.0/24)에서만 허용하고 있어 양호합니다.",
    recommendation_text: "현재 설정을 유지하세요.",
    remediation_cmd: "",
    weight_score: 3, risk_score: 0,
  },
];

const CHECKS_HOST2: CheckResult[] = CHECKS_HOST1.map(c => {
  if (["U-01","U-02","U-03"].includes(c.code)) return { ...c, status: "양호" as CheckStatus, risk_score: 0, command_output: c.command_output + "\n(조치 완료)", evidence_description: "조치 적용 후 양호 상태입니다." };
  return { ...c };
});

const HOST1: ScanHost = {
  host_info: { hostname: "web-server-01", ip: "10.8.0.5", os: "Ubuntu 22.04 LTS", kernel: "5.15.0-101-generic", arch: "x86_64" },
  summary: {
    total: 67, pass: 55, vuln: 7, na: 5, manual: 0,
    max_score: 180, deducted_score: 21,
    compliance_rate: "88.7%", security_score_100: 88.33, security_score_ratio: 0.88,
    grade: "양호", grade_color: "green",
  },
  results: CHECKS_HOST1,
};

const HOST2: ScanHost = {
  host_info: { hostname: "db-server-01", ip: "10.8.0.10", os: "Rocky Linux 8.7", kernel: "4.18.0-477.el8.x86_64", arch: "x86_64" },
  summary: {
    total: 67, pass: 60, vuln: 4, na: 3, manual: 0,
    max_score: 180, deducted_score: 12,
    compliance_rate: "93.7%", security_score_100: 93.33, security_score_ratio: 0.93,
    grade: "양호", grade_color: "green",
  },
  results: CHECKS_HOST2,
};

export const MOCK_REPORT: ScanReport = {
  scan_info: {
    scan_id: "SCAN-20260821-01",
    project_name: "주요정보통신기반시설 시스템 취약점 진단",
    scan_date: "2026-08-21 08:54:17",
    auditor: "심수용, 김성진, 김하영, 정진우, 한주협",
  },
  total_summary: {
    total_hosts: 2,
    total_checks: 134,
    total_pass: 115,
    total_vuln: 11,
    total_na: 8,
    average_compliance_rate: "91.2%",
    average_security_score: 90.83,
    average_security_ratio: 0.91,
    total_grade: "양호",
    total_grade_color: "green",
  },
  hosts: [HOST1, HOST2],
};

// ── Server registry ────────────────────────────────────────────────────────

export const SERVERS: Server[] = [
  { id: "s1", hostname: "web-server-01", ip: "10.8.0.5",  os: "Ubuntu 22.04 LTS",  group: "웹서버", status: "online",  lastScan: "2026-08-21 08:54", lastScanId: "SCAN-20260821-01" },
  { id: "s2", hostname: "db-server-01",  ip: "10.8.0.10", os: "Rocky Linux 8.7",   group: "DB서버", status: "online",  lastScan: "2026-08-21 08:54", lastScanId: "SCAN-20260821-01" },
  { id: "s3", hostname: "app-server-01", ip: "10.8.0.15", os: "Ubuntu 22.04 LTS",  group: "앱서버", status: "online",  lastScan: null, lastScanId: null },
  { id: "s4", hostname: "app-server-02", ip: "10.8.0.16", os: "Rocky Linux 9.2",   group: "앱서버", status: "offline", lastScan: "2026-08-20 14:10", lastScanId: null },
  { id: "s5", hostname: "bastion-01",    ip: "10.8.0.1",  os: "Ubuntu 22.04 LTS",  group: "보안장비", status: "online", lastScan: null, lastScanId: null },
];

// ── Legacy aliases (removed in refactor — kept to prevent stale-cache import errors) ─
export const VULN_CHECKS  = MOCK_REPORT.hosts.flatMap(h => h.results);
export const SCAN_RESULTS = MOCK_REPORT.hosts.map(h => ({
  id: MOCK_REPORT.scan_info.scan_id + "_" + h.host_info.hostname,
  serverId: h.host_info.hostname,
  serverHostname: h.host_info.hostname,
  serverIp: h.host_info.ip,
  startTime: MOCK_REPORT.scan_info.scan_date,
  endTime:   MOCK_REPORT.scan_info.scan_date,
  duration:  "—",
  totalChecks: h.summary.total,
  passCount:   h.summary.pass,
  failCount:   h.summary.vuln,
  warnCount:   h.summary.na,
  score: Math.round(h.summary.security_score_100),
  checks: h.results,
}));

