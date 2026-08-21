import { useState } from "react";
import { VULN_CHECKS, type VulnCheck, type RemediationStatus } from "../data/mockData";

const FAIL_CHECKS = VULN_CHECKS.filter(c => c.status === "fail" || c.status === "warning");

type ApplyState = "idle" | "running" | "done";

export default function RemediationPage() {
  const [checks, setChecks]         = useState<(VulnCheck & { selected: boolean })[]>(FAIL_CHECKS.map(c => ({ ...c, selected: false })));
  const [applyState, setApplyState] = useState<ApplyState>("idle");
  const [applyingId, setApplyingId] = useState<string | null>(null);
  const [logs, setLogs]             = useState<{ id: string; msg: string; type: "info" | "success" | "error" }[]>([]);
  const [showConfirm, setShowConfirm] = useState<boolean>(false);

  const selectedChecks = checks.filter(c => c.selected);
  const allSelected    = checks.length > 0 && checks.every(c => c.selected);

  const toggleAll   = () => setChecks(p => p.map(c => ({ ...c, selected: !allSelected })));
  const toggleCheck = (id: string) => setChecks(p => p.map(c => c.id === id ? { ...c, selected: !c.selected } : c));

  const markRemediated = (ids: string[]) =>
    setChecks(p => p.map(c => ids.includes(c.id) ? { ...c, remediationStatus: "completed" as RemediationStatus } : c));

  const addLog = (id: string, msg: string, type: "info" | "success" | "error") =>
    setLogs(p => [...p, { id, msg, type }]);

  const runRemediation = (targets: (VulnCheck & { selected: boolean })[]) => {
    if (!targets.length) return;
    setApplyState("running");
    setShowConfirm(false);
    let idx = 0;
    const process = () => {
      if (idx >= targets.length) { setApplyState("done"); setApplyingId(null); markRemediated(targets.map(t => t.id)); return; }
      const t = targets[idx];
      setApplyingId(t.id);
      addLog(t.id, `[${t.code}] ${t.title} — 조치 시작...`, "info");
      setTimeout(() => {
        addLog(t.id, `[${t.code}] Playbook 실행: remediate_${t.code.toLowerCase()}.yml`, "info");
        setTimeout(() => {
          const ok = Math.random() > 0.1;
          addLog(t.id, ok ? `[${t.code}] ✓ 조치 완료` : `[${t.code}] ✕ 조치 실패 — 수동 확인 필요`, ok ? "success" : "error");
          idx++;
          setTimeout(process, 300);
        }, 700 + Math.random() * 600);
      }, 300);
    };
    process();
  };

  const sevColors: Record<string, string> = { critical: "#dc2626", high: "#ea580c", medium: "#d97706", low: "#16a34a" };
  const sevBgs:    Record<string, string> = { critical: "#fef2f2", high: "#fff7ed", medium: "#fffbeb", low: "#f0fdf4" };
  const sevLabels: Record<string, string> = { critical: "치명적", high: "높음", medium: "중간", low: "낮음" };

  return (
    <div className="flex-1 overflow-hidden flex flex-col">
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
            style={selectedChecks.length === 0 ? { opacity: 0.4, cursor: "not-allowed" } : { boxShadow: "0 4px 14px rgba(29,78,216,0.25)" }}
            disabled={selectedChecks.length === 0}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            선택 항목 일괄 조치 ({selectedChecks.length})
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-hidden flex">
        {/* Checks list */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-2">
          {checks.map(c => {
            const isApplying = applyingId === c.id;
            const isDone     = c.remediationStatus === "completed";
            const sc  = sevColors[c.severity];
            const sbg = sevBgs[c.severity];
            return (
              <div key={c.id} className="rounded-lg px-4 py-3 flex items-center gap-3 transition-all"
                style={{
                  background: isDone ? "#f0fdf4" : c.selected ? "#f0f7ff" : "#ffffff",
                  border: isDone ? "1px solid #bbf7d0" : c.selected ? "1px solid #bfdbfe" : "1px solid #e2e8f0",
                  opacity: isDone ? 0.65 : 1,
                }}>
                <div onClick={() => !isDone && toggleCheck(c.id)}
                  className="w-5 h-5 rounded border flex items-center justify-center shrink-0"
                  style={{ background: (c.selected || isDone) ? "#1d4ed8" : "#ffffff", borderColor: (c.selected || isDone) ? "#1d4ed8" : "#e2e8f0", cursor: isDone ? "default" : "pointer" }}>
                  {(c.selected || isDone) && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
                </div>
                <div className="w-1 h-10 rounded-full shrink-0" style={{ background: isDone ? "#16a34a" : sc }} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs font-medium" style={{ color: "#475569" }}>{c.code}</span>
                    <span className="text-sm font-medium truncate" style={{ color: isDone ? "#64748b" : "#1e293b" }}>{c.title}</span>
                  </div>
                  <div className="text-xs mt-0.5 truncate" style={{ color: "#64748b" }}>{c.details}</div>
                </div>
                <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                  style={{ background: sbg, color: sc, border: `1px solid ${sc}30` }}>{sevLabels[c.severity]}</span>
                {isDone
                  ? <span className="badge-pass text-[10px] px-2 py-0.5 rounded-full shrink-0">조치 완료</span>
                  : isApplying
                    ? <span className="badge-info text-[10px] px-2 py-0.5 rounded-full shrink-0 animate-pulse-dot">조치 중...</span>
                    : <span className="badge-fail text-[10px] px-2 py-0.5 rounded-full shrink-0">미조치</span>}
                {!isDone && (
                  <button onClick={() => runRemediation([c])} className="btn-secondary text-xs shrink-0 ml-1" disabled={applyState === "running"}>
                    개별 조치
                  </button>
                )}
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
                <div className="text-sm mt-0.5" style={{ color: "#64748b" }}>선택된 {selectedChecks.length}개 항목에 Ansible Playbook을 실행합니다.</div>
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
              <div className="text-xs" style={{ color: "#b45309" }}>⚠ 조치 전 반드시 백업을 확인하세요. 일부 항목은 서비스 재시작이 필요할 수 있습니다.</div>
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
