import { useEffect, useState } from "react";
import { api, type VulnCheck } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type ApplyState = "idle" | "running" | "done";
type LogEntry = { id: string; msg: string; type: "info" | "success" | "error" };

export default function RemediationPage() {
  const { db, servers, loading, error } = useAuditData();
  const [selectedHostId, setSelectedHostId] = useState<string | null>(null);
  const [checks, setChecks] = useState<(VulnCheck & { selected: boolean })[]>([]);
  const [checksLoading, setChecksLoading] = useState(false);
  const [checksError, setChecksError] = useState<string | null>(null);
  const [applyState, setApplyState] = useState<ApplyState>("idle");
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [showConfirm, setShowConfirm] = useState(false);

  useEffect(() => {
    if (servers.length && !selectedHostId) setSelectedHostId(servers[0].id);
  }, [servers, selectedHostId]);

  useEffect(() => {
    if (!db || !selectedHostId) return;
    setChecksLoading(true);
    setChecksError(null);
    api.results(db, selectedHostId)
      .then(rows => setChecks(
        rows.filter(c => c.status === "fail" || c.status === "warning").map(c => ({ ...c, selected: false }))
      ))
      .catch(e => setChecksError(e instanceof Error ? e.message : String(e)))
      .finally(() => setChecksLoading(false));
  }, [db, selectedHostId]);

  const selectedServer = servers.find(s => s.id === selectedHostId);
  const selectedChecks = checks.filter(c => c.selected);
  const allSelected = checks.length > 0 && checks.every(c => c.selected);

  const toggleAll = () => setChecks(p => p.map(c => ({ ...c, selected: !allSelected })));
  const toggleCheck = (id: string) => setChecks(p => p.map(c => c.id === id ? { ...c, selected: !c.selected } : c));

  const addLog = (id: string, msg: string, type: LogEntry["type"]) =>
    setLogs(p => [...p, { id, msg, type }]);

  const runRemediation = async (targets: (VulnCheck & { selected: boolean })[]) => {
    if (!db || !selectedHostId || !selectedServer || !targets.length) return;
    setApplyState("running");
    setShowConfirm(false);
    setLogs([]);
    targets.forEach(t => addLog(t.id, `[${t.code}] ${t.title} — 조치 요청...`, "info"));

    try {
      const results = await api.remediate(db, selectedHostId, selectedServer.hostname, targets.map(t => t.code));
      for (const r of results) {
        const t = targets.find(x => x.code === r.code);
        if (!t) continue;
        if (r.error) {
          addLog(t.id, `[${t.code}] ✕ 조치 실패 — ${r.error}`, "error");
        } else if (r.success) {
          addLog(t.id, `[${t.code}] ✓ 조치 완료 (상태: 양호)`, "success");
        } else {
          addLog(t.id, `[${t.code}] 자동조치 불가 또는 미해결 — 수동 확인 필요 (상태: ${r.status ?? "미확인"})`, "error");
        }
      }
    } catch (e) {
      addLog("_", `일괄 조치 요청 실패: ${e instanceof Error ? e.message : String(e)}`, "error");
    }

    setApplyState("done");
    if (db && selectedHostId) {
      const rows = await api.results(db, selectedHostId);
      setChecks(rows.filter(c => c.status === "fail" || c.status === "warning").map(c => ({ ...c, selected: false })));
    }
  };

  const sevColors: Record<string, string> = { critical: "#dc2626", high: "#ea580c", medium: "#d97706", low: "#16a34a" };
  const sevBgs:    Record<string, string> = { critical: "#fef2f2", high: "#fff7ed", medium: "#fffbeb", low: "#f0fdf4" };
  const sevLabels: Record<string, string> = { critical: "치명적", high: "높음", medium: "중간", low: "낮음" };

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "#64748b" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "#dc2626" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-hidden flex flex-col">
      {/* Host selector */}
      <div className="px-6 pt-4 pb-3 flex items-center gap-3 overflow-x-auto shrink-0" style={{ borderBottom: "1px solid #e2e8f0", background: "#ffffff" }}>
        {servers.map(s => (
          <button key={s.id} onClick={() => setSelectedHostId(s.id)}
            className="px-4 py-2 rounded-lg text-sm font-medium transition-all shrink-0"
            style={s.id === selectedHostId
              ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
              : { background: "#f8fafc", color: "#64748b", border: "1px solid #e2e8f0" }}>
            <span className="font-mono">{s.hostname}</span>
            <span className="ml-2 text-xs opacity-70">· {s.score}점</span>
          </button>
        ))}
      </div>

      {/* Action bar */}
      <div className="px-6 py-4 flex items-center gap-3 shrink-0" style={{ borderBottom: "1px solid #e2e8f0", background: "#ffffff" }}>
        <div onClick={toggleAll} className="w-5 h-5 rounded border flex items-center justify-center cursor-pointer"
          style={{ background: allSelected ? "#1d4ed8" : "#ffffff", borderColor: allSelected ? "#1d4ed8" : "#e2e8f0" }}>
          {allSelected && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
        </div>
        <span className="text-sm" style={{ color: "#64748b" }}>전체 선택</span>
        <div className="h-4 w-px mx-1" style={{ background: "#e2e8f0" }} />
        <span className="text-sm" style={{ color: "#64748b" }}>
          <span className="font-semibold" style={{ color: "#1d4ed8" }}>{selectedChecks.length}</span>개 선택됨
        </span>
        <div className="flex gap-2 ml-auto">
          <button onClick={() => selectedChecks.length > 0 && setShowConfirm(true)}
            className="btn-primary"
            style={selectedChecks.length === 0 || applyState === "running" ? { opacity: 0.4, cursor: "not-allowed" } : { boxShadow: "0 4px 14px rgba(29,78,216,0.25)" }}
            disabled={selectedChecks.length === 0 || applyState === "running"}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            선택 항목 일괄 조치 ({selectedChecks.length})
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-hidden flex">
        {/* Checks list */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-2">
          {checksLoading && <div className="text-center py-16 text-sm" style={{ color: "#94a3b8" }}>불러오는 중...</div>}
          {!checksLoading && checksError && (
            <div className="text-center py-16 text-sm" style={{ color: "#dc2626" }}>불러오기 실패: {checksError}</div>
          )}
          {!checksLoading && !checksError && checks.length === 0 && (
            <div className="text-center py-16 text-sm" style={{ color: "#94a3b8" }}>이 서버에는 취약/주의 항목이 없습니다.</div>
          )}
          {!checksLoading && !checksError && checks.map(c => {
            const sc = sevColors[c.severity];
            const sbg = sevBgs[c.severity];
            return (
              <div key={c.id} className="rounded-lg px-4 py-3 flex items-center gap-3 transition-all"
                style={{
                  background: c.selected ? "#f0f7ff" : "#ffffff",
                  border: c.selected ? "1px solid #bfdbfe" : "1px solid #e2e8f0",
                }}>
                <div onClick={() => toggleCheck(c.id)}
                  className="w-5 h-5 rounded border flex items-center justify-center shrink-0 cursor-pointer"
                  style={{ background: c.selected ? "#1d4ed8" : "#ffffff", borderColor: c.selected ? "#1d4ed8" : "#e2e8f0" }}>
                  {c.selected && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
                </div>
                <div className="w-1 h-10 rounded-full shrink-0" style={{ background: sc }} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs font-medium" style={{ color: "#475569" }}>{c.code}</span>
                    <span className="text-sm font-medium truncate" style={{ color: "#1e293b" }}>{c.title}</span>
                  </div>
                  <div className="text-xs mt-0.5 truncate" style={{ color: "#64748b" }}>{c.details}</div>
                </div>
                <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                  style={{ background: sbg, color: sc, border: `1px solid ${sc}30` }}>{sevLabels[c.severity]}</span>
                <button onClick={() => runRemediation([c])} className="btn-secondary text-xs shrink-0 ml-1" disabled={applyState === "running"}>
                  개별 조치
                </button>
              </div>
            );
          })}
        </div>

        {/* Log panel */}
        <div className="w-72 shrink-0 flex flex-col" style={{ borderLeft: "1px solid #e2e8f0" }}>
          <div className="px-4 py-3 flex items-center justify-between" style={{ borderBottom: "1px solid #f1f5f9", background: "#fafafa" }}>
            <span className="font-display font-semibold text-sm" style={{ color: "#0f172a" }}>조치 로그</span>
            {applyState === "running" && (
              <div className="flex items-center gap-1.5 text-xs font-medium" style={{ color: "#1d4ed8" }}>
                <div className="w-1.5 h-1.5 rounded-full animate-pulse-dot" style={{ background: "#2563eb" }} />실행 중
              </div>
            )}
            {applyState === "done" && <span className="badge-pass text-xs px-2 py-0.5 rounded-full">완료</span>}
          </div>
          <div className="flex-1 overflow-y-auto p-3 font-mono text-xs space-y-0.5" style={{ background: "#f8fafc" }}>
            {logs.length === 0 ? (
              <div className="text-center mt-12 text-xs" style={{ color: "#94a3b8" }}>조치 실행 시<br />로그가 표시됩니다.</div>
            ) : logs.map((l, i) => (
              <div key={i} style={{ color: l.type === "success" ? "#15803d" : l.type === "error" ? "#b91c1c" : "#374151" }}>{l.msg}</div>
            ))}
          </div>
          {applyState === "done" && (
            <div className="p-3" style={{ borderTop: "1px solid #f1f5f9" }}>
              <div className="text-xs" style={{ color: "#64748b" }}>
                성공 <span style={{ color: "#15803d", fontWeight: 600 }}>{logs.filter(l => l.type === "success").length}</span>개 ·
                실패 <span style={{ color: "#b91c1c", fontWeight: 600 }}>{logs.filter(l => l.type === "error").length}</span>개
              </div>
            </div>
          )}
        </div>
      </div>

      {showConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: "rgba(15,23,42,0.45)" }}>
          <div className="card w-96 space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0" style={{ background: "#eff6ff" }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1d4ed8" strokeWidth="2">
                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                </svg>
              </div>
              <div>
                <div className="font-semibold" style={{ color: "#0f172a" }}>일괄 조치 확인</div>
                <div className="text-sm mt-0.5" style={{ color: "#64748b" }}>
                  <span className="font-mono">{selectedServer?.hostname}</span>에 선택된 {selectedChecks.length}개 항목을 실제로 조치합니다.
                </div>
              </div>
            </div>
            <div className="p-3 rounded-lg space-y-1 max-h-36 overflow-y-auto" style={{ background: "#f8fafc", border: "1px solid #e2e8f0" }}>
              {selectedChecks.map(c => (
                <div key={c.id} className="text-xs flex items-center gap-2" style={{ color: "#64748b" }}>
                  <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: sevColors[c.severity] }} />
                  <span className="font-mono font-medium">{c.code}</span>
                  <span>{c.title}</span>
                </div>
              ))}
            </div>
            <div className="p-3 rounded-lg" style={{ background: "#fffbeb", border: "1px solid #fde68a" }}>
              <div className="text-xs" style={{ color: "#b45309" }}>⚠ 실제 서버 설정을 변경합니다 (파일 백업 후 적용). 서비스 재시작이 필요할 수 있습니다.</div>
            </div>
            <div className="flex gap-3">
              <button onClick={() => runRemediation(selectedChecks)} className="btn-primary flex-1 justify-center">조치 실행</button>
              <button onClick={() => setShowConfirm(false)} className="btn-secondary flex-1 justify-center">취소</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
