export type Severity = "critical" | "high" | "medium" | "low";
export type CheckStatus = "pass" | "fail" | "warning" | "manual";

export interface Server {
  id: string;
  hostname: string;
  ip: string;
  os: string;
  group: string;
  // "초기 설정" 시점에 systemctl로 감지한 DB 엔진 힌트("mysql"/"postgresql"/
  // "mysql,postgresql"/"") - 확정 결과가 아니라 힌트. 서버 등록 직후(초기
  // 설정 전)에는 항상 빈 문자열.
  detectedDb: string;
  status: "online" | "offline" | "scanning" | "error";
  lastScan: string | null;
  totalChecks: number;
  passCount: number;
  failCount: number;
  warnCount: number;
  score: number;
}

export interface VulnCheck {
  id: string;
  code: string;
  category: string;
  title: string;
  description: string;
  severity: Severity;
  status: CheckStatus;
  details: string;
  recommendation: string;
  remediationStatus: "pending" | "in_progress" | "completed" | "failed";
  // 진단이 "검토(manual)"로 판정한 항목을 사람이 최종 확정한 결과 -
  // "양호"/"취약"/"" (아직 미확정). status 자체(원본 진단 판정)는 그대로
  // 두고 별도로 기록되며, 점수 계산에는 이 값이 있으면 이 값이 우선한다.
  manualVerdict: "양호" | "취약" | "";
  manualReason: string;
  manualAt: string | null;
}

// status(원본 진단 판정)는 절대 안 지운다(자동 진단 근거 보존 목적) - 대신
// "이 항목을 지금 pass/fail 중 뭐로 취급해야 하는가"가 필요한 모든 곳(카운트,
// 필터, 정렬, "조치 필요" 판단 등)은 이 함수를 통해서만 판단한다.
// backend/db.py::recompute_host_score()의 eff_status와 동일한 규칙
// (manualVerdict가 있으면 그게 우선)을 프론트에서도 그대로 따른다.
const VERDICT_TO_STATUS: Record<"양호" | "취약", CheckStatus> = { "양호": "pass", "취약": "fail" };
export const effectiveStatus = (c: VulnCheck): CheckStatus =>
  c.manualVerdict ? VERDICT_TO_STATUS[c.manualVerdict] : c.status;

export interface Scan {
  id: number;
  scan_id: string;
  project_name: string;
  scan_date: string;
  average_security_score: number;
  total_grade: string;
  total_hosts: number;
}

export interface RemediateResult {
  code: string;
  success: boolean;
  status: string | null;
  error?: string;
}

export interface ScanRunResult {
  success: boolean;
  output: string;
  aborted?: boolean;
}

const BASE = "/api";
const TOKEN_KEY = "sa_token";

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

function authHeaders(): Record<string, string> {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

// FastAPI가 HTTPException(status, detail)로 보내는 실패 사유를 최대한 그대로
// 보여준다 - 없으면(네트워크 에러 등 detail이 없는 응답) 상태코드 기반 기본 문구로.
async function throwWithDetail(path: string, res: Response): Promise<never> {
  const data = await res.json().catch(() => null);
  const detail = data && typeof data.detail === "string" ? data.detail : null;
  throw new Error(detail || `API ${path} failed: ${res.status}`);
}

async function getJSON<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { headers: authHeaders() });
  if (!res.ok) return throwWithDetail(path, res);
  return res.json();
}

async function postJSON<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });
  if (!res.ok) return throwWithDetail(path, res);
  return res.json();
}

async function putJSON<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });
  if (!res.ok) return throwWithDetail(path, res);
  return res.json();
}

export const api = {
  companies: () => getJSON<string[]>("/companies"),
  scans: (db: string) => getJSON<Scan[]>(`/scans?db=${encodeURIComponent(db)}`),
  servers: (db: string, scanId: string) =>
    getJSON<Server[]>(`/servers?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}`),
  results: (db: string, hostId: string) =>
    getJSON<VulnCheck[]>(`/results?db=${encodeURIComponent(db)}&host_id=${encodeURIComponent(hostId)}`),
  reportUrl: (db: string, scanId: string, format: "json" | "xlsx" | "docx") =>
    `${BASE}/report?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}&format=${format}`,
  remediate: (db: string, hostId: string, hostname: string, codes: string[]) =>
    postJSON<RemediateResult[]>("/remediate", { db, host_id: Number(hostId), hostname, codes }),
  manualVerdict: (db: string, hostId: string, code: string, verdict: "양호" | "취약", reason: string) =>
    postJSON<{ ok: boolean }>("/manual-verdict", { db, host_id: Number(hostId), code, verdict, reason }),
  runScan: (hosts: string[]) => postJSON<ScanRunResult>("/scan/run", { hosts }),
  abortScan: () => postJSON<{ ok: boolean; aborted: boolean }>("/scan/abort", {}),
  login: async (username: string, password: string) => {
    const res = await fetch(`${BASE}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    if (!res.ok) {
      // 계정 잠금(423) 등은 서버가 detail에 구체적인 안내 문구를 담아 보내므로
      // 그대로 보여준다 - 없을 때만 상태코드 기반 기본 문구로 대체한다.
      const data = await res.json().catch(() => null);
      const detail = data && typeof data.detail === "string" ? data.detail : null;
      throw new Error(detail || (res.status === 401 ? "아이디 또는 비밀번호가 올바르지 않습니다." : `로그인 실패: ${res.status}`));
    }
    const data = await res.json();
    localStorage.setItem(TOKEN_KEY, data.accessToken);
    return data as { accessToken: string; username: string; expiresIn: number };
  },
  logout: async () => {
    try {
      await fetch(`${BASE}/auth/logout`, { method: "POST", headers: authHeaders() });
    } finally {
      localStorage.removeItem(TOKEN_KEY);
    }
  },
  addServer: (db: string, scanId: string, ip: string) =>
    postJSON<{ ok: boolean; hostname: string; os: string; pending: boolean }>("/servers", { db, scan_id: scanId, ip }),
  // "초기 설정" 버튼: hostname/OS 수집 + sudo NOPASSWD 설정을 한 번에 실행한다.
  provisionServer: (db: string, hostId: string, sudoPassword: string) =>
    postJSON<{ ok: boolean; hostname: string; os: string; group: string; detectedDb: string }>(
      `/servers/${hostId}/provision`, { db, sudo_password: sudoPassword }
    ),
  deleteServer: async (db: string, hostId: string) => {
    const res = await fetch(`${BASE}/servers/${hostId}?db=${encodeURIComponent(db)}`, {
      method: "DELETE",
      headers: authHeaders(),
    });
    if (!res.ok) throw new Error(`API delete server failed: ${res.status}`);
    return res.json();
  },
  config: () => getJSON<Record<string, unknown>>("/config"),
  saveConfig: (config: Record<string, unknown>) => putJSON<{ ok: boolean; config: Record<string, unknown> }>("/config", config),
  reportBlobUrl: async (db: string, scanId: string, format: "json" | "xlsx" | "docx") => {
    const res = await fetch(api.reportUrl(db, scanId, format), { headers: authHeaders() });
    if (!res.ok) throw new Error(`report download failed: ${res.status}`);
    const blob = await res.blob();
    return URL.createObjectURL(blob);
  },
};
