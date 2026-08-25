import { useEffect, useState } from "react";
import { api, type VulnCheck } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type ApplyState = "idle" | "running" | "done";
type LogEntry = { id: string; msg: string; type: "info" | "success" | "error" };

// 진단 결과 페이지와 동일한 축 - 코드 접두사로 Linux(U-)/DB(D-)를 나눈다.
// 카테고리명이 두 챕터에서 겹치는 건 아니지만(여긴 심각도로 묶으므로), U/D
// 항목이 한 목록에 섞여 있으면 "지금 Linux 서버를 보는지 DB를 보는지"가
// 안 보여서 결과 페이지와 결을 맞추기 위해 여기도 동일하게 나눈다.
type Platform = "linux" | "db";
const platformOf = (code: string): Platform => (code.startsWith("D-") ? "db" : "linux");

export default function RemediationPage() {
  const { db, servers, loading, error } = useAuditData();
  const [selectedHostId, setSelectedHostId] = useState<string | null>(null);
  const [checks, setChecks] = useState<(VulnCheck & { selected: boolean })[]>([]);
  const [checksLoading, setChecksLoading] = useState(false);
  const [checksError, setChecksError] = useState<string | null>(null);
  const [applyState, setApplyState] = useState<ApplyState>("idle");
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [showConfirm, setShowConfirm] = useState(false);
  const [collapsedCats, setCollapsedCats] = useState<Set<string>>(new Set());
  const [platformFilter, setPlatformFilter] = useState<Platform>("linux");
  const [sevFilter, setSevFilter] = useState("전체");
  const [serverSearch, setServerSearch] = useState("");

  const codeNum = (code: string) => parseInt(code.replace(/\D/g, ""), 10) || 0;
  const toggleCat = (cat: string) => setCollapsedCats(prev => {
    const next = new Set(prev);
    next.has(cat) ? next.delete(cat) : next.add(cat);
    return next;
  });

  useEffect(() => {
    if (servers.length && !selectedHostId) setSelectedHostId(servers[0].id);
  }, [servers, selectedHostId]);

  useEffect(() => {
    if (!db || !selectedHostId) return;
    setChecksLoading(true);
    setChecksError(null);
    api.results(db, selectedHostId)
      .then(rows => setChecks(rows.map(c => ({ ...c, selected: false }))))
      .catch(e => setChecksError(e instanceof Error ? e.message : String(e)))
      .finally(() => setChecksLoading(false));
  }, [db, selectedHostId]);

  // Linux/DB 탭 전환 시 선택을 비운다 - 안 그러면 안 보이는 탭에서 골라놓은
  // 항목이 "일괄 조치"에 몰래 같이 끼어들 수 있다.
  const linuxCount = checks.filter(c => platformOf(c.code) === "linux" && (c.status === "fail" || c.status === "manual")).length;
  const dbCount = checks.filter(c => platformOf(c.code) === "db" && (c.status === "fail" || c.status === "manual")).length;
  const switchPlatform = (p: Platform) => {
    setPlatformFilter(p);
    setSevFilter("전체");
    setChecks(prev => prev.map(c => ({ ...c, selected: false })));
  };

  // 조치 대상은 "취약(fail)"과 "검토 필요(manual)"만 - 이미 양호(pass)하거나
  // 해당 없음(warning=N/A)인 항목까지 여기 다 보이면, 진단 결과 페이지의
  // "취약 N개"와 숫자가 안 맞고 이미 괜찮은 항목을 조치 대상으로 선택할 수도
  // 있었다(실측된 불일치 - 예: 취약 21개인데 여기는 67개 전부가 보임).
  const visibleChecks = checks
    .filter(c => platformOf(c.code) === platformFilter)
    .filter(c => c.status === "fail" || c.status === "manual")
    .filter(c => sevFilter === "전체" || c.severity === sevFilter);
  const SEV_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };
  const sevGroupLabels: Record<string, string> = { critical: "치명적", high: "높음", medium: "중간", low: "낮음" };
  const sevOrder = (["critical", "high", "medium", "low"] as const).filter(s => visibleChecks.some(c => c.severity === s));
  const grouped = sevOrder
    .map(sev => ({ cat: sevGroupLabels[sev], items: visibleChecks.filter(c => c.severity === sev).sort((a, b) => codeNum(a.code) - codeNum(b.code)) }))
    .filter(g => g.items.length > 0);

  const selectedServer = servers.find(s => s.id === selectedHostId);

  // 실제 자동조치를 걸 수 있는 항목은 "취약(fail)"뿐이다 - "검토(manual)"는
  // 자동 진단이 확정 판정을 못 내린 상태라, 그걸 대상으로 "조치"를 거는 건
  // 애초에 성립하지 않는다(기존엔 버튼을 눌러도 백엔드가 "자동조치 불가"로
  // 되돌려주는 것으로 사후에 막았는데, 처음부터 선택/버튼 자체를 막는 게 더
  // 명확하다). 목록에는 여전히 보이고 "수동 검토" 배지도 그대로 남는다 -
  // 조치 대상이 아닐 뿐 존재를 숨기는 게 아니다.
  const actionableChecks = visibleChecks.filter(c => c.status === "fail");
  const selectedChecks = checks.filter(c => c.selected && c.status === "fail");
  const allSelected = actionableChecks.length > 0 && actionableChecks.every(c => c.selected);

  // actionableChecks와 동일한 조건(플랫폼 + 취약 상태 + 심각도)이어야 한다 -
  // 조건을 빼먹으면 "전체 선택"이 화면에 안 보이는 다른 탭/검토/양호/N-A
  // 항목까지 몰래 선택해버린다.
  const toggleAll = () => setChecks(p => p.map(c =>
    platformOf(c.code) === platformFilter && c.status === "fail" && (sevFilter === "전체" || c.severity === sevFilter)
      ? { ...c, selected: !allSelected } : c
  ));
  // "검토(manual)" 항목은 선택 자체가 안 되게 막는다 - 화면(체크박스 disabled)
  // 뿐 아니라 여기서도 막아서, 혹시 다른 경로로 toggleCheck가 호출되더라도
  // manual 항목이 selected=true가 될 수 없다.
  const toggleCheck = (id: string) => setChecks(p => p.map(c => c.id === id && c.status === "fail" ? { ...c, selected: !c.selected } : c));

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
      setChecks(rows.map(c => ({ ...c, selected: false })));
    }
  };

  const sevColors:  Record<string, string> = { critical: "var(--tint-red-text)", high: "var(--tint-orange-text)", medium: "var(--tint-amber-text)", low: "var(--tint-green-text)" };
  const sevBgs:     Record<string, string> = { critical: "var(--tint-red-bg)", high: "var(--tint-orange-bg)", medium: "var(--tint-amber-bg)", low: "var(--tint-green-bg)" };
  const sevBorders: Record<string, string> = { critical: "var(--tint-red-border)", high: "var(--tint-orange-border)", medium: "var(--tint-amber-border)", low: "var(--tint-green-border)" };
  const sevLabels:  Record<string, string> = { critical: "치명적", high: "높음", medium: "중간", low: "낮음" };

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--tint-red-text)" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-hidden flex flex-col">
      {/* Host selector */}
      <div className="px-6 pt-4 pb-3 flex items-center gap-2 shrink-0" style={{ borderBottom: "1px solid var(--border)", background: "var(--card)" }}>
        <input className="input text-xs" style={{ maxWidth: 180 }} placeholder="호스트명 또는 IP 검색..." value={serverSearch} onChange={e => setServerSearch(e.target.value)} />
        <select className="input text-xs" style={{ maxWidth: 240, cursor: "pointer" }} value={selectedHostId ?? ""} onChange={e => setSelectedHostId(e.target.value)}>
          {servers.filter(s => s.hostname.includes(serverSearch) || s.ip.includes(serverSearch)).map(s => (
            <option key={s.id} value={s.id}>{s.hostname} ({s.ip}) · {s.score}점</option>
          ))}
        </select>
        <div className="h-4 w-px mx-1" style={{ background: "var(--border)" }} />
        <div className="flex gap-2">
          {([["linux", "Linux 서버", linuxCount], ["db", "DB", dbCount]] as [Platform, string, number][]).map(([key, label, count]) => (
            <button key={key} onClick={() => switchPlatform(key)}
              className="px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all"
              style={platformFilter === key
                ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)" }
                : { background: "var(--muted)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
              {label} <span style={{ opacity: 0.7 }}>({count})</span>
            </button>
          ))}
        </div>
      </div>

      {/* Action bar */}
      <div className="px-6 py-4 flex items-center gap-3 shrink-0" style={{ borderBottom: "1px solid var(--border)", background: "var(--card)" }}>
        <div onClick={toggleAll} className="w-5 h-5 rounded border flex items-center justify-center cursor-pointer"
          style={{ background: allSelected ? "#1d4ed8" : "var(--card)", borderColor: allSelected ? "#1d4ed8" : "var(--border)" }}>
          {allSelected && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
        </div>
        <span className="text-sm" style={{ color: "var(--muted-foreground)" }}>취약 항목 전체 선택</span>
        <div className="h-4 w-px mx-1" style={{ background: "var(--border)" }} />
        <select className="input text-xs" style={{ maxWidth: 120, cursor: "pointer" }} value={sevFilter} onChange={e => setSevFilter(e.target.value)}>
          <option value="전체">전체</option>
          <option value="high">높음</option>
          <option value="medium">중간</option>
          <option value="low">낮음</option>
        </select>
        <div className="h-4 w-px mx-1" style={{ background: "var(--border)" }} />
        <span className="text-sm" style={{ color: "var(--muted-foreground)" }}>
          <span className="font-semibold" style={{ color: "var(--tint-blue-text)" }}>{selectedChecks.length}</span>개 선택됨
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
          {checksLoading && <div className="text-center py-16 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>}
          {!checksLoading && checksError && (
            <div className="text-center py-16 text-sm" style={{ color: "var(--tint-red-text)" }}>불러오기 실패: {checksError}</div>
          )}
          {!checksLoading && !checksError && visibleChecks.length === 0 && (
            <div className="text-center py-16 text-sm" style={{ color: "var(--muted-foreground)" }}>조건에 맞는 항목이 없습니다.</div>
          )}
          {!checksLoading && !checksError && grouped.map(({ cat, items }) => {
            const catCollapsed = collapsedCats.has(cat);
            const catSelected = items.filter(c => c.selected).length;
            return (
              <div key={cat}>
                <div onClick={() => toggleCat(cat)}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer select-none"
                  style={{ background: "var(--muted)" }}>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="var(--muted-foreground)" strokeWidth="2.5"
                    style={{ transform: catCollapsed ? "rotate(-90deg)" : "rotate(0deg)", transition: "transform 0.15s" }}>
                    <polyline points="6,9 12,15 18,9"/>
                  </svg>
                  <span className="text-sm font-semibold" style={{ color: "var(--foreground)" }}>{cat}</span>
                  <span className="text-xs" style={{ color: "var(--muted-foreground)" }}>{items.length}개</span>
                  {catSelected > 0 && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-full font-medium" style={{ background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)" }}>{catSelected}개 선택됨</span>
                  )}
                </div>
                {!catCollapsed && (
                  <div className="space-y-2 mt-1.5">
                    {items.map(c => {
                      const sc = sevColors[c.severity];
                      const sbg = sevBgs[c.severity];
                      const sbd = sevBorders[c.severity];
                      return (
                        <div key={c.id} className="rounded-lg px-4 py-3 flex items-center gap-3 transition-all"
                          style={{
                            background: c.selected ? "var(--tint-blue-bg)" : "var(--card)",
                            border: c.selected ? "1px solid var(--tint-blue-border)" : "1px solid var(--border)",
                          }}>
                          <div onClick={() => c.status === "fail" && toggleCheck(c.id)}
                            className={`w-5 h-5 rounded border flex items-center justify-center shrink-0 ${c.status === "fail" ? "cursor-pointer" : "cursor-not-allowed opacity-40"}`}
                            title={c.status === "fail" ? undefined : "검토(수동 확인) 항목은 자동 조치 대상이 아닙니다."}
                            style={{ background: c.selected ? "#1d4ed8" : "var(--card)", borderColor: c.selected ? "#1d4ed8" : "var(--border)" }}>
                            {c.selected && <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3"><polyline points="20,6 9,17 4,12"/></svg>}
                          </div>
                          <div className="w-1 h-10 rounded-full shrink-0" style={{ background: sc }} />
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="font-mono text-xs font-medium" style={{ color: "var(--text-secondary)" }}>{c.code}</span>
                              <span className="text-sm font-medium truncate" style={{ color: "var(--foreground)" }}>{c.title}</span>
                            </div>
                            <div className="text-xs mt-0.5 truncate" style={{ color: "var(--muted-foreground)" }}>{c.details}</div>
                          </div>
                          {c.status === "manual" && (
                            <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                              style={{ background: "var(--tint-indigo-bg)", color: "var(--tint-indigo-text)", border: "1px solid var(--tint-indigo-border)" }}>
                              수동 검토
                            </span>
                          )}
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: sbg, color: sc, border: `1px solid ${sbd}` }}>{sevLabels[c.severity]}</span>
                          {/* "검토" 항목도 버튼 모양은 그대로 두되(자리가 빈 텍스트로
                              바뀌면 목록이 들쭉날쭉해 보인다) 클릭만 막고 색을
                              흐리게 해서 "조치 대상 아님"을 표시한다. */}
                          <button onClick={() => c.status === "fail" && runRemediation([c])}
                            className="btn-secondary text-xs shrink-0 ml-1"
                            disabled={applyState === "running" || c.status !== "fail"}
                            title={c.status === "fail" ? undefined : "검토(수동 확인) 항목은 자동 조치 대상이 아닙니다."}
                            style={c.status === "fail" ? undefined : { opacity: 0.4, cursor: "not-allowed", background: "var(--muted)", color: "var(--text-tertiary)", borderColor: "var(--border)" }}>
                            개별 조치
                          </button>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* Log panel */}
        <div className="w-72 shrink-0 flex flex-col" style={{ borderLeft: "1px solid var(--border)" }}>
          <div className="px-4 py-3 flex items-center justify-between" style={{ borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
            <span className="font-display font-semibold text-sm" style={{ color: "var(--foreground)" }}>조치 로그</span>
            {applyState === "running" && (
              <div className="flex items-center gap-1.5 text-xs font-medium" style={{ color: "var(--tint-blue-text)" }}>
                <div className="w-1.5 h-1.5 rounded-full animate-pulse-dot" style={{ background: "var(--tint-blue-text)" }} />실행 중
              </div>
            )}
            {applyState === "done" && <span className="badge-pass text-xs px-2 py-0.5 rounded-full">완료</span>}
          </div>
          <div className="flex-1 overflow-y-auto p-3 font-mono text-xs space-y-0.5" style={{ background: "var(--muted)" }}>
            {logs.length === 0 ? (
              <div className="text-center mt-12 text-xs" style={{ color: "var(--muted-foreground)" }}>조치 실행 시<br />로그가 표시됩니다.</div>
            ) : logs.map((l, i) => (
              <div key={i} style={{ color: l.type === "success" ? "var(--tint-green-text)" : l.type === "error" ? "var(--tint-red-text)" : "var(--foreground)" }}>{l.msg}</div>
            ))}
          </div>
          {applyState === "done" && (
            <div className="p-3" style={{ borderTop: "1px solid var(--border)" }}>
              <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>
                성공 <span style={{ color: "var(--tint-green-text)", fontWeight: 600 }}>{logs.filter(l => l.type === "success").length}</span>개 ·
                실패 <span style={{ color: "var(--tint-red-text)", fontWeight: 600 }}>{logs.filter(l => l.type === "error").length}</span>개
              </div>
            </div>
          )}
        </div>
      </div>

      {showConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: "rgba(15,23,42,0.45)" }}>
          <div className="card w-96 space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0" style={{ background: "var(--tint-blue-bg)" }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--tint-blue-text)" strokeWidth="2">
                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                </svg>
              </div>
              <div>
                <div className="font-semibold" style={{ color: "var(--foreground)" }}>일괄 조치 확인</div>
                <div className="text-sm mt-0.5" style={{ color: "var(--muted-foreground)" }}>
                  <span className="font-mono">{selectedServer?.hostname}</span>에 선택된 {selectedChecks.length}개 항목을 실제로 조치합니다.
                </div>
              </div>
            </div>
            <div className="p-3 rounded-lg space-y-1 max-h-36 overflow-y-auto" style={{ background: "var(--muted)", border: "1px solid var(--border)" }}>
              {selectedChecks.map(c => (
                <div key={c.id} className="text-xs flex items-center gap-2" style={{ color: "var(--muted-foreground)" }}>
                  <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: sevColors[c.severity] }} />
                  <span className="font-mono font-medium">{c.code}</span>
                  <span>{c.title}</span>
                </div>
              ))}
            </div>
            <div className="p-3 rounded-lg" style={{ background: "var(--tint-amber-bg)", border: "1px solid var(--tint-amber-border)" }}>
              <div className="text-xs" style={{ color: "var(--tint-amber-text)" }}>⚠ 실제 서버 설정을 변경합니다 (파일 백업 후 적용). 서비스 재시작이 필요할 수 있습니다.</div>
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
