import { useState } from "react";
import { api } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type ScanState = "idle" | "running" | "done" | "error";

const LOGS_KEY = "sa_scan_logs";
const STATE_KEY = "sa_scan_state";

export default function ScanPage() {
  const { servers, loading, error } = useAuditData();
  const [selected, setSelected]   = useState<string[]>([]);
  const [scanState, setScanState] = useState<ScanState>(() => (localStorage.getItem(STATE_KEY) as ScanState) || "idle");
  const [logs, setLogs]           = useState<string[]>(() => {
    try { return JSON.parse(localStorage.getItem(LOGS_KEY) || "[]"); } catch { return []; }
  });

  const toggleServer = (id: string) => setSelected(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id]);

  const addLog = (msg: string) => {
    const time = new Date().toLocaleTimeString("ko-KR", { hour12: false });
    setLogs(prev => {
      const next = [...prev, `[${time}] ${msg}`];
      localStorage.setItem(LOGS_KEY, JSON.stringify(next));
      return next;
    });
  };

  const setAndPersistState = (s: ScanState) => {
    setScanState(s);
    localStorage.setItem(STATE_KEY, s);
  };

  const clearLogs = () => {
    setLogs([]);
    localStorage.removeItem(LOGS_KEY);
  };

  const startScan = async () => {
    if (selected.length === 0) return;
    const targets = servers.filter(s => selected.includes(s.id));
    const hostnames = [...new Set(targets.map(s => s.hostname))];
    const ips = [...new Set(targets.map(s => s.ip))].join(", ");
    setAndPersistState("running");
    clearLogs();
    addLog(`▶ ${ips} 진단 실행 중 (Ansible playbook, 완료까지 수 분 소요될 수 있음)...`);
    try {
      const result = await api.runScan(hostnames);
      if (result.success) {
        setAndPersistState("done");
        addLog("✓ 진단 완료. DB에 결과 저장됨 — 결과 탭에서 확인하세요.");
      } else {
        setAndPersistState("error");
        addLog("✕ 진단 실패:");
        result.output.split("\n").slice(-20).forEach(line => line.trim() && addLog(`  ${line}`));
      }
    } catch (e) {
      setAndPersistState("error");
      addLog(`✕ 요청 실패: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "#dc2626" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-5">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Server selection */}
        <div className="card" style={{ padding: 0 }}>
          <div className="flex items-center justify-between px-5 py-4" style={{ borderBottom: "1px solid var(--border)" }}>
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>진단 대상 서버 선택</h2>
            <div className="flex gap-2">
              <button onClick={() => setSelected(servers.map(s => s.id))} className="text-xs px-2 py-1 rounded" style={{ color: "#1d4ed8", background: "#eff6ff" }}>전체 선택</button>
              <button onClick={() => setSelected([])} className="text-xs px-2 py-1 rounded" style={{ color: "var(--muted-foreground)", background: "var(--muted)" }}>초기화</button>
            </div>
          </div>
          <div>
            {servers.map(s => {
              const isChecked = selected.includes(s.id);
              return (
                <div key={s.id} onClick={() => toggleServer(s.id)}
                  className="table-row cursor-pointer"
                  style={{ gridTemplateColumns: "auto 1fr auto", background: isChecked ? "rgba(29,78,216,0.14)" : undefined }}>
                  <div className="w-5 h-5 rounded border flex items-center justify-center mr-1"
                    style={{ background: isChecked ? "#1d4ed8" : "var(--card)", borderColor: isChecked ? "#1d4ed8" : "var(--border)" }}>
                    {isChecked && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-sm font-medium" style={{ color: "var(--foreground)" }}>{s.ip}</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded" style={{ background: "var(--muted)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>{s.group}</span>
                    </div>
                    <div className="text-xs mt-0.5 font-mono" style={{ color: "var(--muted-foreground)" }}>{s.os}</div>
                  </div>
                  <div className="text-xs font-medium" style={{ color: "#16a34a" }}>{s.status === "online" ? "온라인" : s.status}</div>
                </div>
              );
            })}
          </div>
          <div className="px-5 py-3" style={{ borderTop: "1px solid var(--border)", background: "var(--muted)" }}>
            <div className="text-xs" style={{ color: "var(--muted-foreground)" }}><span style={{ color: "#1d4ed8", fontWeight: 600 }}>{selected.length}</span>개 서버 선택됨</div>
          </div>
        </div>

        {/* Control */}
        <div className="space-y-4">
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>진단 설정</h2>
            <p className="text-xs" style={{ color: "var(--muted-foreground)" }}>
              선택한 서버에 Ansible playbook(<code className="font-mono">01_run_audit.yml</code>)을 실행해 U-01~U-67 전 항목을 진단하고, 결과를 DB에 저장합니다.
            </p>
          </div>

          <div className="card space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>진단 실행</h2>
              {scanState === "done" && <span className="badge-pass text-xs px-2 py-1 rounded-full">완료</span>}
              {scanState === "error" && <span className="badge-fail text-xs px-2 py-1 rounded-full">실패</span>}
            </div>

            {scanState === "running" && (
              <div className="flex items-center gap-2 text-xs" style={{ color: "var(--muted-foreground)" }}>
                <div className="w-3.5 h-3.5 rounded-full border-2 animate-spin" style={{ borderColor: "#dbeafe", borderTopColor: "#2563eb" }} />
                진단 실행 중... (완료까지 기다려주세요)
              </div>
            )}

            <div className="flex gap-3">
              <button onClick={startScan} disabled={selected.length === 0 || scanState === "running"} className="btn-primary"
                style={selected.length === 0 || scanState === "running" ? { opacity: 0.4, cursor: "not-allowed" } : { boxShadow: "0 4px 16px rgba(29,78,216,0.25)" }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polygon points="5,3 19,12 5,21"/></svg>
                {scanState === "done" || scanState === "error" ? "재진단 실행" : "진단 시작"}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Logs */}
      <div className="card" style={{ padding: 0 }}>
        <div className="flex items-center justify-between px-5 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
          <h2 className="font-display font-semibold text-sm" style={{ color: "var(--foreground)" }}>진단 로그</h2>
          <button onClick={clearLogs} className="text-xs" style={{ color: "var(--text-tertiary)" }}>지우기</button>
        </div>
        <div className="font-mono text-xs p-4 overflow-y-auto" style={{ height: 220, color: "var(--text-secondary)", background: "var(--muted)" }}>
          {logs.length === 0 ? (
            <div className="text-center mt-8" style={{ color: "var(--text-tertiary)" }}>진단을 시작하면 여기에 로그가 표시됩니다.</div>
          ) : logs.map((log, i) => (
            <div key={i} className="mb-0.5" style={{
              color: log.includes("✓") ? "#15803d" : log.includes("▶") ? "#1d4ed8" : log.includes("✕") ? "#b91c1c" : "var(--text-secondary)"
            }}>{log}</div>
          ))}
        </div>
      </div>
    </div>
  );
}
