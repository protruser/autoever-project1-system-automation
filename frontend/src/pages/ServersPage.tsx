import { useEffect, useRef, useState } from "react";
import { api, type Server } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type Tab = "list" | "add-single" | "add-bulk";

// hostname이 아직 IP 그대로면 백그라운드 hostname/OS 수집이 안 끝난 상태
const isPending = (s: Server) => s.hostname === s.ip;

export default function ServersPage() {
  const { db, scan, servers: realServers, loading, error } = useAuditData();
  const [tab, setTab] = useState<Tab>("list");
  const [servers, setServers] = useState<Server[]>([]);
  useEffect(() => { setServers(realServers); }, [realServers]);

  // 등록 직후 백그라운드에서 채워지는 hostname/OS를 목록에 반영하기 위해
  // 잠깐(최대 ~1분) 짧은 주기로 다시 불러온다. 영구히 실패한 항목 때문에
  // 무한 폴링하지 않도록 시도 횟수를 제한한다.
  const pollAttempts = useRef(0);
  useEffect(() => {
    if (!db || !scan) return;
    if (!servers.some(isPending)) { pollAttempts.current = 0; return; }
    if (pollAttempts.current >= 20) return;
    const t = setTimeout(async () => {
      pollAttempts.current += 1;
      const refreshed = await api.servers(db, scan.scan_id);
      setServers(refreshed);
    }, 3000);
    return () => clearTimeout(t);
  }, [db, scan, servers]);

  const [search, setSearch] = useState("");
  const [groupFilter, setGroupFilter] = useState("전체");
  const [showConfirm, setShowConfirm] = useState<string | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [form, setForm] = useState({ ip: "" });
  const [addError, setAddError] = useState<string | null>(null);
  const [addSuccess, setAddSuccess] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [bulkText, setBulkText] = useState("");
  const [bulkAdding, setBulkAdding] = useState(false);
  const [bulkResult, setBulkResult] = useState<string | null>(null);

  const IP_RE = /^\d{1,3}(\.\d{1,3}){3}$/;

  const handleBulkAdd = async () => {
    if (!db || !scan) return;
    setBulkAdding(true);
    setBulkResult(null);
    const lines = bulkText.split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("#"));
    let ok = 0, fail = 0;
    const errors: string[] = [];
    // 등록 자체는 IP만으로 즉시 끝나고, hostname/OS는 서버에서 백그라운드로 채운다.
    // 그래도 여러 건을 동시에 쏴서 등록 응답을 더 빨리 받는다.
    await Promise.all(lines.map(async (ip) => {
      if (!IP_RE.test(ip)) { fail++; errors.push(`${ip} — 올바른 IP 형식이 아님`); return; }
      try {
        await api.addServer(db, scan.scan_id, ip);
        ok++;
      } catch (e) {
        fail++;
        errors.push(`${ip}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }));
    const refreshed = await api.servers(db, scan.scan_id);
    setServers(refreshed);
    setBulkResult(`${ok}건 등록 완료. hostname/OS는 백그라운드에서 순차적으로 채워집니다(잠시 후 목록이 자동 갱신됩니다).${fail ? ` ${fail}건 실패 — ${errors.slice(0, 3).join("; ")}` : ""}`);
    setBulkAdding(false);
  };

  const groups  = ["전체", ...Array.from(new Set(servers.map(s => s.group)))];
  const filtered = servers.filter(s =>
    (groupFilter === "전체" || s.group === groupFilter) &&
    (s.hostname.includes(search) || s.ip.includes(search))
  );

  const handleAddSingle = async () => {
    if (!db || !scan) return;
    setAdding(true);
    setAddError(null);
    setAddSuccess(null);
    try {
      await api.addServer(db, scan.scan_id, form.ip.trim());
      const refreshed = await api.servers(db, scan.scan_id);
      setServers(refreshed);
      setAddSuccess(`'${form.ip.trim()}'을(를) 등록했습니다. hostname/OS는 백그라운드에서 수집 중이며, 확인되는 대로 목록이 자동으로 갱신됩니다.`);
      setForm({ ip: "" });
    } catch (e) {
      setAddError(e instanceof Error ? e.message : "등록 실패");
    } finally {
      setAdding(false);
    }
  };

  const statusMeta = {
    online:   { color: "#16a34a", bg: "#f0fdf4", label: "온라인" },
    offline:  { color: "var(--text-tertiary)", bg: "var(--muted)", label: "오프라인" },
    scanning: { color: "#d97706", bg: "#fffbeb", label: "진단중" },
    error:    { color: "#dc2626", bg: "#fef2f2", label: "오류" },
  };

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "#dc2626" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-5">
      {/* Tab bar */}
      <div className="flex items-center gap-1 p-1 rounded-lg" style={{ background: "var(--card)", border: "1px solid var(--border)", width: "fit-content" }}>
        {([["list", "서버 목록"], ["add-single", "+ 단일 등록"], ["add-bulk", "+ 일괄 등록"]] as [Tab, string][]).map(([id, label]) => (
          <button key={id} onClick={() => setTab(id)}
            className="px-4 py-2 rounded-md text-sm font-medium transition-all"
            style={tab === id
              ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
              : { color: "var(--muted-foreground)", border: "1px solid transparent" }}>
            {label}
          </button>
        ))}
      </div>

      {tab === "list" && (
        <>
          <div className="flex items-center gap-3">
            <input className="input" style={{ maxWidth: 280 }} placeholder="호스트명 또는 IP 검색..." value={search} onChange={e => setSearch(e.target.value)} />
            <div className="flex gap-1">
              {groups.map(g => (
                <button key={g} onClick={() => setGroupFilter(g)}
                  className="px-3 py-1.5 rounded-md text-xs font-medium transition-all"
                  style={groupFilter === g
                    ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
                    : { background: "var(--card)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
                  {g}
                </button>
              ))}
            </div>
            <div className="ml-auto text-xs" style={{ color: "var(--text-tertiary)" }}>총 {filtered.length}대</div>
          </div>

          <div className="card" style={{ padding: 0 }}>
            <div className="grid px-5 py-3 text-xs font-semibold uppercase tracking-wider"
              style={{ gridTemplateColumns: "2fr 1fr 1.5fr 1fr 1fr 1fr auto", color: "var(--text-secondary)", borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
              <div>서버</div><div>그룹</div><div>OS</div><div>상태</div><div>마지막 진단</div><div>보안 점수</div><div></div>
            </div>
            {filtered.map((s) => {
              const sm = statusMeta[s.status];
              return (
                <div key={s.id} className="table-row" style={{ gridTemplateColumns: "2fr 1fr 1.5fr 1fr 1fr 1fr auto" }}>
                  <div>
                    <div className="text-sm font-medium" style={{ color: "var(--foreground)" }}>{s.hostname}</div>
                    <div className="font-mono text-xs" style={{ color: "var(--muted-foreground)" }}>{s.ip}</div>
                  </div>
                  <div><span className="text-xs px-2 py-1 rounded" style={{ background: "var(--muted)", color: "var(--text-secondary)", border: "1px solid var(--border)" }}>{s.group}</span></div>
                  <div className="text-xs" style={{ color: "var(--text-secondary)" }}>{s.os}</div>
                  <div>
                    <span className="flex items-center gap-1.5 text-xs font-medium w-fit px-2 py-0.5 rounded-full" style={{ color: sm.color, background: sm.bg }}>
                      <span className="w-1.5 h-1.5 rounded-full" style={{ background: sm.color }} />{sm.label}
                    </span>
                  </div>
                  <div className="text-xs font-mono" style={{ color: "var(--muted-foreground)" }}>{s.lastScan ?? "—"}</div>
                  <div>
                    {s.score > 0
                      ? <span className="font-mono text-sm font-bold" style={{ color: s.score >= 80 ? "#15803d" : s.score >= 60 ? "#b45309" : "#b91c1c" }}>{s.score}</span>
                      : <span className="font-mono text-sm" style={{ color: "var(--text-tertiary)" }}>—</span>}
                  </div>
                  <div className="flex items-center gap-1">
                    <button className="p-1.5 rounded text-xs transition-colors hover:text-blue-600" style={{ color: "var(--muted-foreground)" }} title="연결 테스트">
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
                    </button>
                    <button onClick={() => setShowConfirm(s.id)} className="p-1.5 rounded text-xs transition-colors hover:text-red-500" style={{ color: "var(--muted-foreground)" }} title="삭제">
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="3,6 5,6 21,6"/><path d="M19,6v14a2,2,0,01-2,2H7a2,2,0,01-2-2V6m3,0V4a2,2,0,012-2h4a2,2,0,012,2v2"/></svg>
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}

      {tab === "add-single" && (
        <div className="max-w-xl">
          <div className="card space-y-5">
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>서버 단일 등록</h2>
            <p className="text-xs" style={{ color: "var(--muted-foreground)" }}>IP만 입력하면 즉시 등록되고, hostname/운영체제는 백그라운드에서 접속해 자동으로 수집합니다.</p>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>IP 주소 *</label>
              <input className="input" placeholder="192.168.1.12" value={form.ip} onChange={e => setForm(p => ({ ...p, ip: e.target.value }))} />
            </div>
            {addError && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "#fef2f2", color: "#b91c1c" }}>{addError}</div>
            )}
            {addSuccess && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "#f0fdf4", color: "#15803d" }}>{addSuccess}</div>
            )}
            <div className="flex gap-3 pt-2">
              <button onClick={handleAddSingle} className="btn-primary" disabled={!form.ip || adding}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                {adding ? "등록 중..." : "서버 등록"}
              </button>
              <button onClick={() => setTab("list")} className="btn-secondary">목록으로</button>
            </div>
          </div>
        </div>
      )}

      {tab === "add-bulk" && (
        <div className="max-w-2xl">
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>서버 일괄 등록</h2>
            <p className="text-xs" style={{ color: "var(--muted-foreground)" }}>한 줄에 IP 하나씩 입력합니다. 등록은 즉시 끝나고, hostname/운영체제는 백그라운드에서 각 서버로 접속해 순차적으로 채워집니다. 끝내 접속에 실패한 서버는 IP가 그대로 hostname으로 표시됩니다.</p>
            <textarea
              className="input font-mono text-xs resize-none"
              rows={10}
              value={bulkText}
              onChange={e => setBulkText(e.target.value)}
              placeholder={"192.168.2.10\n192.168.2.11\n192.168.2.20"}
              style={{ lineHeight: 1.6 }}
            />
            {bulkResult && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "#f0fdf4", color: "#15803d" }}>{bulkResult}</div>
            )}
            <div className="flex gap-3">
              <button onClick={handleBulkAdd} disabled={bulkAdding} className="btn-primary" style={bulkAdding ? { opacity: 0.6, cursor: "not-allowed" } : undefined}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                {bulkAdding ? "등록 중..." : "일괄 등록"}
              </button>
              <button className="btn-secondary">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17,8 12,3 7,8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
                파일 업로드
              </button>
              <button onClick={() => setTab("list")} className="btn-secondary">취소</button>
            </div>
          </div>
        </div>
      )}

      {showConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: "rgba(15,23,42,0.5)" }}>
          <div className="card w-80 space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-lg flex items-center justify-center" style={{ background: "#fef2f2" }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#dc2626" strokeWidth="2"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
              </div>
              <div>
                <div className="font-semibold text-sm" style={{ color: "var(--foreground)" }}>서버 삭제 확인</div>
                <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>이 작업은 되돌릴 수 없습니다. (진단 결과도 함께 삭제됩니다)</div>
              </div>
            </div>
            {deleteError && (
              <div className="text-xs px-2 py-1.5 rounded" style={{ background: "#fef2f2", color: "#b91c1c" }}>{deleteError}</div>
            )}
            <div className="flex gap-2 pt-1">
              <button onClick={async () => {
                if (!db || !showConfirm) return;
                setDeleteError(null);
                try {
                  await api.deleteServer(db, showConfirm);
                  setServers(p => p.filter(s => s.id !== showConfirm));
                  setShowConfirm(null);
                } catch (e) {
                  setDeleteError(e instanceof Error ? e.message : "삭제 실패");
                }
              }} className="btn-danger flex-1 justify-center">삭제</button>
              <button onClick={() => { setShowConfirm(null); setDeleteError(null); }} className="btn-secondary flex-1 justify-center">취소</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
