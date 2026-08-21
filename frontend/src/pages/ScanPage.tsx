import { useState, useEffect, useRef } from "react";
import { useAuditData } from "../hooks/useAuditData";

type ScanState = "idle" | "running" | "done";

const TASKS = [
  "SSH 연결 테스트...",
  "계정 관리 항목 진단 중 (U-01 ~ U-12)...",
  "파일/디렉터리 권한 점검 중 (U-13 ~ U-24)...",
  "서비스 취약점 분석 중 (U-25 ~ U-38)...",
  "패치 상태 확인 중 (U-39 ~ U-46)...",
  "로그 설정 점검 중 (U-47 ~ U-57)...",
  "네트워크 서비스 점검 중 (U-58 ~ U-72)...",
  "결과 집계 및 보고서 생성 중...",
];

export default function ScanPage() {
  const { servers, loading, error } = useAuditData();
  const [selected, setSelected]           = useState<string[]>([]);
  const [scanState, setScanState]         = useState<ScanState>("idle");
  const [taskIdx, setTaskIdx]             = useState(0);
  const [progress, setProgress]           = useState(0);
  const [logs, setLogs]                   = useState<string[]>([]);
  const [currentServer, setCurrentServer] = useState(0);
  const logsRef = useRef<HTMLDivElement>(null);

  const toggleServer = (id: string) => setSelected(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id]);

  useEffect(() => {
    if (logsRef.current) logsRef.current.scrollTop = logsRef.current.scrollHeight;
  }, [logs]);

  const addLog = (msg: string) => {
    const time = new Date().toLocaleTimeString("ko-KR", { hour12: false });
    setLogs(prev => [...prev, `[${time}] ${msg}`]);
  };

  const startScan = () => {
    if (selected.length === 0) return;
    setScanState("running"); setTaskIdx(0); setProgress(0); setLogs([]); setCurrentServer(0);
  };

  useEffect(() => {
    if (scanState !== "running") return;
    const target = servers.filter(s => selected.includes(s.id));
    if (!target.length) return;
    const cs = target[currentServer];
    if (!cs) { setScanState("done"); addLog("✓ 모든 서버 진단 완료."); return; }

    addLog(`▶ ${cs.hostname} (${cs.ip}) 진단 시작`);
    let ti = 0;
    const interval = setInterval(() => {
      if (ti < TASKS.length) {
        addLog(`  ${cs.hostname}: ${TASKS[ti]}`);
        setTaskIdx(ti);
        setProgress(Math.round(((ti + 1) / TASKS.length) * 100 * (currentServer + 1) / target.length));
        ti++;
      } else {
        clearInterval(interval);
        addLog(`✓ ${cs.hostname} 진단 완료 — 보안 점수: ${Math.floor(Math.random() * 30 + 55)}점`);
        setCurrentServer(prev => {
          const next = prev + 1;
          if (next >= target.length) { setScanState("done"); addLog("✓ 모든 서버 진단 완료. 결과 탭에서 확인하세요."); }
          return next;
        });
      }
    }, 400);
    return () => clearInterval(interval);
  }, [scanState, currentServer]);

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "#64748b" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "#dc2626" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-5">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Server selection */}
        <div className="card" style={{ padding: 0 }}>
          <div className="flex items-center justify-between px-5 py-4" style={{ borderBottom: "1px solid #f1f5f9" }}>
            <h2 className="font-display font-semibold" style={{ color: "#0f172a" }}>진단 대상 서버 선택</h2>
            <div className="flex gap-2">
              <button onClick={() => setSelected(servers.map(s => s.id))} className="text-xs px-2 py-1 rounded" style={{ color: "#1d4ed8", background: "#eff6ff" }}>전체 선택</button>
              <button onClick={() => setSelected([])} className="text-xs px-2 py-1 rounded" style={{ color: "#64748b", background: "#f1f5f9" }}>초기화</button>
            </div>
          </div>
          <div>
            {servers.map(s => {
              const isChecked  = selected.includes(s.id);
              const isDisabled = s.status === "offline";
              const stColor    = s.status === "online" ? "#16a34a" : s.status === "offline" ? "#94a3b8" : "#d97706";
              return (
                <div key={s.id} onClick={() => !isDisabled && toggleServer(s.id)}
                  className="table-row cursor-pointer"
                  style={{ gridTemplateColumns: "auto 1fr auto", opacity: isDisabled ? 0.45 : 1, background: isChecked ? "#f0f7ff" : undefined }}>
                  <div className="w-5 h-5 rounded border flex items-center justify-center mr-1"
                    style={{ background: isChecked ? "#1d4ed8" : "#ffffff", borderColor: isChecked ? "#1d4ed8" : "#e2e8f0" }}>
                    {isChecked && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-sm font-medium" style={{ color: "#1e293b" }}>{s.hostname}</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded" style={{ background: "#f1f5f9", color: "#64748b", border: "1px solid #e2e8f0" }}>{s.group}</span>
                    </div>
                    <div className="text-xs mt-0.5 font-mono" style={{ color: "#64748b" }}>{s.ip} · {s.os}</div>
                  </div>
                  <div className="text-xs font-medium" style={{ color: stColor }}>
                    {s.status === "online" ? "온라인" : s.status === "offline" ? "오프라인" : "진단중"}
                  </div>
                </div>
              );
            })}
          </div>
          <div className="px-5 py-3" style={{ borderTop: "1px solid #f1f5f9", background: "#fafafa" }}>
            <div className="text-xs" style={{ color: "#64748b" }}><span style={{ color: "#1d4ed8", fontWeight: 600 }}>{selected.length}</span>개 서버 선택됨</div>
          </div>
        </div>

        {/* Config + control */}
        <div className="space-y-4">
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "#0f172a" }}>진단 설정</h2>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>진단 기준</label>
              <select className="input" style={{ cursor: "pointer" }}>
                <option>주요정보통신기반시설 보호대책 가이드 (2023)</option>
                <option>ISMS-P 기술적 보호조치</option>
                <option>CIS Benchmarks Level 1</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>진단 항목</label>
              <div className="grid grid-cols-2 gap-2">
                {["계정 관리 (U-01~12)","파일/디렉터리 (U-13~24)","서비스 관리 (U-25~38)","패치 관리 (U-39~46)","로그 관리 (U-47~57)","네트워크 (U-58~72)"].map(cat => (
                  <label key={cat} className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: "#374151" }}>
                    <input type="checkbox" className="accent-blue-600" defaultChecked />{cat}
                  </label>
                ))}
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>동시 실행 서버 수</label>
              <div className="flex gap-2">
                {[1,3,5,10].map(n => (
                  <button key={n} className="px-3 py-1.5 rounded text-sm font-mono"
                    style={n === 3
                      ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
                      : { background: "#f8fafc", color: "#64748b", border: "1px solid #e2e8f0" }}>
                    {n}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="card space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-display font-semibold" style={{ color: "#0f172a" }}>진단 실행</h2>
              {scanState === "done" && <span className="badge-pass text-xs px-2 py-1 rounded-full">완료</span>}
            </div>

            {scanState === "running" && (
              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs" style={{ color: "#64748b" }}>
                  <span>{TASKS[Math.min(taskIdx, TASKS.length - 1)]}</span>
                  <span className="font-mono font-semibold" style={{ color: "#1d4ed8" }}>{progress}%</span>
                </div>
                <div className="progress-bar">
                  <div className="progress-fill" style={{ width: `${progress}%`, background: "linear-gradient(90deg, #2563eb, #0284c7)" }} />
                </div>
                <div className="flex items-center gap-2 text-xs" style={{ color: "#64748b" }}>
                  <div className="w-2 h-2 rounded-full animate-pulse-dot" style={{ background: "#2563eb" }} />
                  {servers.find(s => s.id === selected[currentServer])?.hostname ?? "진단 중..."} 진단 중
                </div>
              </div>
            )}

            <div className="flex gap-3">
              {scanState !== "running" ? (
                <button onClick={startScan} disabled={selected.length === 0} className="btn-primary"
                  style={selected.length === 0 ? { opacity: 0.4, cursor: "not-allowed" } : { boxShadow: "0 4px 16px rgba(29,78,216,0.25)" }}>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polygon points="5,3 19,12 5,21"/></svg>
                  {scanState === "done" ? "재진단 실행" : "진단 시작"}
                </button>
              ) : (
                <button onClick={() => setScanState("idle")} className="btn-danger">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><rect x="3" y="3" width="18" height="18"/></svg>
                  중단
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Logs */}
      <div className="card" style={{ padding: 0 }}>
        <div className="flex items-center justify-between px-5 py-3" style={{ borderBottom: "1px solid #f1f5f9" }}>
          <h2 className="font-display font-semibold text-sm" style={{ color: "#0f172a" }}>실시간 진단 로그</h2>
          <div className="flex items-center gap-3">
            {scanState === "running" && (
              <div className="flex items-center gap-1.5 text-xs font-medium" style={{ color: "#16a34a" }}>
                <div className="w-1.5 h-1.5 rounded-full animate-pulse-dot" style={{ background: "#16a34a" }} />실시간
              </div>
            )}
            <button onClick={() => setLogs([])} className="text-xs" style={{ color: "#94a3b8" }}>지우기</button>
          </div>
        </div>
        <div ref={logsRef} className="font-mono text-xs p-4 overflow-y-auto" style={{ height: 220, color: "#374151", background: "#f8fafc" }}>
          {logs.length === 0 ? (
            <div className="text-center mt-8" style={{ color: "#94a3b8" }}>진단을 시작하면 여기에 로그가 표시됩니다.</div>
          ) : logs.map((log, i) => (
            <div key={i} className="mb-0.5" style={{
              color: log.includes("✓") ? "#15803d" : log.includes("▶") ? "#1d4ed8" : log.includes("✕") ? "#b91c1c" : "#374151"
            }}>{log}</div>
          ))}
        </div>
      </div>
    </div>
  );
}
