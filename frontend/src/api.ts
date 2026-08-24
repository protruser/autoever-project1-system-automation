export type Severity = "critical" | "high" | "medium" | "low";
export type CheckStatus = "pass" | "fail" | "warning" | "manual";

export interface Server {
  id: string;
  hostname: string;
  ip: string;
  os: string;
  group: string;
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
}

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

async function getJSON<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { headers: authHeaders() });
  if (!res.ok) throw new Error(`API ${path} failed: ${res.status}`);
  return res.json();
}

async function postJSON<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`API ${path} failed: ${res.status}`);
  return res.json();
}

async function putJSON<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`API ${path} failed: ${res.status}`);
  return res.json();
}

export const api = {
  companies: () => getJSON<string[]>("/companies"),
  scans: (db: string) => getJSON<Scan[]>(`/scans?db=${encodeURIComponent(db)}`),
  servers: (db: string, scanId: string) =>
    getJSON<Server[]>(`/servers?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}`),
  results: (db: string, hostId: string) =>
    getJSON<VulnCheck[]>(`/results?db=${encodeURIComponent(db)}&host_id=${encodeURIComponent(hostId)}`),
  reportUrl: (db: string, scanId: string, format: "json" | "csv" | "docx") =>
    `${BASE}/report?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}&format=${format}`,
  remediate: (db: string, hostId: string, hostname: string, codes: string[]) =>
    postJSON<RemediateResult[]>("/remediate", { db, host_id: Number(hostId), hostname, codes }),
  runScan: (hosts: string[]) => postJSON<ScanRunResult>("/scan/run", { hosts }),
  login: async (username: string, password: string) => {
    const res = await fetch(`${BASE}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    if (!res.ok) throw new Error(res.status === 401 ? "아이디 또는 비밀번호가 올바르지 않습니다." : `로그인 실패: ${res.status}`);
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
  reportBlobUrl: async (db: string, scanId: string, format: "json" | "csv" | "docx") => {
    const res = await fetch(api.reportUrl(db, scanId, format), { headers: authHeaders() });
    if (!res.ok) throw new Error(`report download failed: ${res.status}`);
    const blob = await res.blob();
    return URL.createObjectURL(blob);
  },
};
