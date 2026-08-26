import { useEffect, useState } from "react";
import { api, type Server } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type Tab = "list" | "add-single" | "add-bulk";

// hostname이 아직 IP 그대로면 "초기 설정"(hostname/OS 수집 + sudo 설정)이 아직 안 끝난 상태
const isPending = (s: Server) => s.hostname === s.ip;

// detectedDb("mysql"/"postgresql"/"mysql,postgresql")를 배지 텍스트로 변환.
// "초기 설정" 시점의 가벼운 힌트일 뿐이라 확정 아이콘이 아니라 물음표 톤의
// 라벨로 표시하고, 정확한 값은 진단 실행 결과(D-항목)를 보라고 안내한다.
const dbLabel = (detectedDb: string): string | null => {
  if (!detectedDb) return null;
  const names = detectedDb.split(",").map(e => e === "mysql" ? "MySQL" : e === "postgresql" ? "PostgreSQL" : e);
  return names.join(" · ");
};

// 서버 등록 전 사전 준비(SSH 키 교환 + sudo 설정) 안내 팝업을 세션당 1회만
// 자동으로 띄우기 위한 플래그. 이후엔 "?" 아이콘으로 언제든 다시 열 수 있다.
const GUIDE_SEEN_KEY = "sa_servers_guide_seen";

export default function ServersPage() {
  const { db, scan, servers: realServers, loading, error } = useAuditData();
  const [tab, setTab] = useState<Tab>("list");
  const [servers, setServers] = useState<Server[]>([]);
  useEffect(() => { setServers(realServers); }, [realServers]);

  const [showGuide, setShowGuide] = useState(false);
  useEffect(() => {
    try {
      if (!sessionStorage.getItem(GUIDE_SEEN_KEY)) setShowGuide(true);
    } catch {
      setShowGuide(true); // sessionStorage 접근 불가 시에도 안내는 보여준다
    }
  }, []);
  const closeGuide = () => {
    setShowGuide(false);
    try { sessionStorage.setItem(GUIDE_SEEN_KEY, "1"); } catch { /* ignore */ }
  };

  // "초기 설정" 모달 - hostname/OS 수집 + sudo NOPASSWD 설정을 한 번에 실행한다.
  // sudo 비밀번호는 이 요청 한 번에만 쓰이고 어디에도 저장하지 않는다.
  const [provisionTarget, setProvisionTarget] = useState<Server | null>(null);
  const [sudoPassword, setSudoPassword] = useState("");
  const [provisioning, setProvisioning] = useState(false);
  const [provisionError, setProvisionError] = useState<string | null>(null);

  const openProvision = (s: Server) => {
    setProvisionTarget(s);
    setSudoPassword("");
    setProvisionError(null);
  };
  const closeProvision = () => {
    if (provisioning) return;
    setProvisionTarget(null);
    setSudoPassword("");
    setProvisionError(null);
  };
  const submitProvision = async () => {
    // 비밀번호는 선택 입력 - 이미 NOPASSWD sudo인 서버는 백엔드가 먼저 비밀번호
    // 없이 시도해서 그냥 성공한다(setup_sudoers의 "무비번 프로브"). 정말 필요한
    // 서버에서만 비워두면 뒤에서 실패 사유로 안내된다.
    if (!db || !scan || !provisionTarget) return;
    setProvisioning(true);
    setProvisionError(null);
    try {
      await api.provisionServer(db, provisionTarget.id, sudoPassword);
      const refreshed = await api.servers(db, scan.scan_id);
      setServers(refreshed);
      setProvisionTarget(null);
      setSudoPassword("");
    } catch (e) {
      setProvisionError(e instanceof Error ? e.message : "초기 설정 실패");
    } finally {
      setProvisioning(false);
    }
  };

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
    // 등록 자체는 IP만으로 즉시 끝난다. hostname/OS 수집과 sudo 설정은 목록에서
    // 서버마다 "초기 설정" 버튼으로 따로 진행한다(비밀번호가 필요해 자동화 불가).
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
    setBulkResult(`${ok}건 등록 완료. 목록에서 서버별로 "초기 설정" 버튼을 눌러 hostname/OS 수집과 sudo 설정을 진행하세요.${fail ? ` ${fail}건 실패 — ${errors.slice(0, 3).join("; ")}` : ""}`);
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
      setAddSuccess(`'${form.ip.trim()}'을(를) 등록했습니다. 목록에서 "초기 설정" 버튼을 눌러 hostname/OS 수집과 sudo 설정을 진행하세요.`);
      setForm({ ip: "" });
    } catch (e) {
      setAddError(e instanceof Error ? e.message : "등록 실패");
    } finally {
      setAdding(false);
    }
  };

  const statusMeta = {
    online:   { color: "var(--tint-green-text)", bg: "var(--tint-green-bg)", label: "온라인" },
    offline:  { color: "var(--text-tertiary)", bg: "var(--muted)", label: "오프라인" },
    scanning: { color: "var(--tint-amber-text)", bg: "var(--tint-amber-bg)", label: "진단중" },
    error:    { color: "var(--tint-red-text)", bg: "var(--tint-red-bg)", label: "오류" },
  };

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--tint-red-text)" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-5">
      {/* Tab bar */}
      <div className="flex items-center gap-2">
        <div className="flex items-center gap-1 p-1 rounded-lg" style={{ background: "var(--card)", border: "1px solid var(--border)", width: "fit-content" }}>
          {([["list", "서버 목록"], ["add-single", "+ 단일 등록"], ["add-bulk", "+ 일괄 등록"]] as [Tab, string][]).map(([id, label]) => (
            <button key={id} onClick={() => setTab(id)}
              className="px-4 py-2 rounded-md text-sm font-medium transition-all"
              style={tab === id
                ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)" }
                : { color: "var(--muted-foreground)", border: "1px solid transparent" }}>
              {label}
            </button>
          ))}
        </div>
        <button onClick={() => setShowGuide(true)} title="서버 등록 전 사전 준비(SSH 키 교환 · sudo 설정) 안내"
          className="w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold transition-colors hover:text-blue-600"
          style={{ color: "var(--muted-foreground)", border: "1px solid var(--border)", background: "var(--card)" }}>
          ?
        </button>
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
                    ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)" }
                    : { background: "var(--card)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
                  {g}
                </button>
              ))}
            </div>
            <div className="ml-auto text-xs" style={{ color: "var(--text-tertiary)" }}>총 {filtered.length}대</div>
          </div>

          <div className="card" style={{ padding: 0 }}>
            <div className="grid px-4 py-3 text-xs font-semibold uppercase tracking-wider"
              style={{ gridTemplateColumns: "minmax(0,2fr) minmax(0,0.9fr) minmax(0,1.4fr) minmax(0,0.9fr) minmax(0,0.9fr) minmax(0,1fr) 88px", color: "var(--text-secondary)", borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
              <div>호스트명</div><div>그룹</div><div>OS</div><div>상태</div><div>마지막 진단</div><div>보안 점수</div><div></div>
            </div>
            {filtered.map((s) => {
              const sm = statusMeta[s.status];
              return (
                <div key={s.id} className="table-row" style={{ gridTemplateColumns: "minmax(0,2fr) minmax(0,0.9fr) minmax(0,1.4fr) minmax(0,0.9fr) minmax(0,0.9fr) minmax(0,1fr) 88px" }}>
                  <div>
                    <div className="flex items-center gap-1.5">
                      <span className="text-sm font-medium" style={{ color: "var(--foreground)" }}>{s.hostname}</span>
                      {isPending(s) && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded-full font-medium" style={{ color: "var(--tint-amber-text)", background: "var(--tint-amber-bg)" }}>설정 필요</span>
                      )}
                    </div>
                    <div className="font-mono text-xs mt-0.5" style={{ color: "var(--muted-foreground)" }}>{s.ip}</div>
                  </div>
                  <div><span className="text-xs px-2 py-0.5 rounded" style={{ background: "var(--muted)", color: "var(--text-secondary)", border: "1px solid var(--border)" }}>{s.group}</span></div>
                  <div className="flex items-center gap-1.5 min-w-0">
                    <span className="text-xs truncate" style={{ color: "var(--text-secondary)" }} title={s.os}>{s.os}</span>
                    {dbLabel(s.detectedDb) && (
                      <span className="text-[10px] px-1.5 py-0.5 rounded-full font-medium shrink-0"
                        style={{ color: "var(--tint-indigo-text)", background: "var(--tint-indigo-bg)", border: "1px solid var(--tint-indigo-border)" }}
                        title="초기 설정 시점에 감지한 힌트 - 정확한 결과는 진단 실행 후 확인하세요.">
                        DB: {dbLabel(s.detectedDb)}
                      </span>
                    )}
                  </div>
                  <div>
                    <span className="flex items-center gap-1.5 text-xs font-medium w-fit px-2 py-0.5 rounded-full" style={{ color: sm.color, background: sm.bg }}>
                      <span className="w-1.5 h-1.5 rounded-full" style={{ background: sm.color }} /><span className="ml-1">{sm.label}</span>
                    </span>
                  </div>
                  <div className="text-xs font-mono" style={{ color: "var(--muted-foreground)" }}>{s.lastScan ?? "—"}</div>
                  <div>
                    {s.score > 0
                      ? <span className="font-mono text-sm font-bold" style={{ color: s.score >= 80 ? "var(--tint-green-text)" : s.score >= 60 ? "var(--tint-amber-text)" : "var(--tint-red-text)" }}>{s.score}</span>
                      : <span className="font-mono text-sm" style={{ color: "var(--text-tertiary)" }}>—</span>}
                  </div>
                  <div className="flex items-center gap-1">
                    <button onClick={() => openProvision(s)} className="p-1.5 rounded text-xs transition-colors hover:text-blue-600"
                      style={{ color: isPending(s) ? "var(--tint-amber-text)" : "var(--muted-foreground)" }} title="초기 설정 (hostname/OS 수집 + sudo 설정)">
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="7.5" cy="15.5" r="5.5"/><path d="M21 2l-9.6 9.6"/><path d="M15.5 7.5l3 3L22 7l-3-3"/></svg>
                    </button>
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
            <p className="text-xs" style={{ color: "var(--muted-foreground)" }}>IP만 입력하면 즉시 등록됩니다. hostname/운영체제 수집과 sudo 설정은 등록 후 목록에서 "초기 설정" 버튼으로 진행하세요.</p>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>IP 주소 *</label>
              <input className="input" placeholder="192.168.1.12" value={form.ip} onChange={e => setForm(p => ({ ...p, ip: e.target.value }))} />
            </div>
            {addError && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "var(--tint-red-bg)", color: "var(--tint-red-text)" }}>{addError}</div>
            )}
            {addSuccess && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "var(--tint-green-bg)", color: "var(--tint-green-text)" }}>{addSuccess}</div>
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
            <p className="text-xs" style={{ color: "var(--muted-foreground)" }}>한 줄에 IP 하나씩 입력합니다. 등록은 즉시 끝나고, hostname/운영체제 수집과 sudo 설정은 등록 후 목록에서 서버별로 "초기 설정" 버튼으로 진행합니다.</p>
            <textarea
              className="input font-mono text-xs resize-none"
              rows={10}
              value={bulkText}
              onChange={e => setBulkText(e.target.value)}
              placeholder={"192.168.2.10\n192.168.2.11\n192.168.2.20"}
              style={{ lineHeight: 1.6 }}
            />
            {bulkResult && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "var(--tint-green-bg)", color: "var(--tint-green-text)" }}>{bulkResult}</div>
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
              <div className="w-9 h-9 rounded-lg flex items-center justify-center" style={{ background: "var(--tint-red-bg)" }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--tint-red-text)" strokeWidth="2"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
              </div>
              <div>
                <div className="font-semibold text-sm" style={{ color: "var(--foreground)" }}>서버 삭제 확인</div>
                <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>이 작업은 되돌릴 수 없습니다. (진단 결과도 함께 삭제됩니다)</div>
              </div>
            </div>
            {deleteError && (
              <div className="text-xs px-2 py-1.5 rounded" style={{ background: "var(--tint-red-bg)", color: "var(--tint-red-text)" }}>{deleteError}</div>
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

      {showGuide && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(15,23,42,0.5)" }} onClick={closeGuide}>
          <div className="card space-y-4" style={{ maxWidth: 560, width: "100%", maxHeight: "85vh", overflowY: "auto" }} onClick={e => e.stopPropagation()}>
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 text-base font-bold" style={{ background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)" }}>
                  ?
                </div>
                <div>
                  <div className="font-semibold text-sm" style={{ color: "var(--foreground)" }}>서버 등록 전 사전 준비</div>
                  <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>SSH 키 교환과 sudo 설정이 안 되어 있으면 진단·조치가 실패합니다.</div>
                </div>
              </div>
              <button onClick={closeGuide} className="p-1 rounded flex-shrink-0" style={{ color: "var(--muted-foreground)" }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            </div>

            <div className="space-y-3 text-xs" style={{ color: "var(--text-secondary)" }}>
              <div>
                <div className="font-semibold mb-1.5" style={{ color: "var(--foreground)" }}>1. SSH 키 교환 (Tailscale 대상 서버당 최초 1회, 수동)</div>
                <pre className="font-mono text-xs p-2.5 rounded overflow-x-auto" style={{ background: "var(--muted)", color: "var(--text-secondary)" }}>
{`ssh-copy-id -i ~/.ssh/id_rsa.pub user@<대상 서버 Tailscale IP>`}
                </pre>
                <div className="mt-1.5">컨트롤 노드에 이미 있는 키를 그대로 쓰면 됩니다(새로 만들 필요 없음). 키가 없는 서버는 애초에 Ansible이 접속할 수 없어 자동화 대상이 아닙니다 - 등록 전에 미리 해두세요.</div>
              </div>

              <div>
                <div className="font-semibold mb-1.5" style={{ color: "var(--foreground)" }}>2. IP 등록 후, 목록에서 "초기 설정" 버튼</div>
                <div>키 <span style={{ color: "var(--tint-amber-text)" }}>🔑</span> 아이콘 버튼을 누르고 sudo 비밀번호를 한 번 입력하면 hostname/OS 수집과 NOPASSWD sudo 설정이 한 번에 끝나고, 그룹도 OS에 맞게 자동 배정됩니다. 비밀번호는 그 순간에만 쓰이고 저장되지 않습니다.</div>
              </div>
            </div>

            <div className="flex justify-end pt-1">
              <button onClick={closeGuide} className="btn-secondary">확인했습니다</button>
            </div>
          </div>
        </div>
      )}

      {provisionTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ background: "rgba(15,23,42,0.5)" }} onClick={closeProvision}>
          <div className="card w-96 space-y-4" onClick={e => e.stopPropagation()}>
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: "var(--tint-blue-bg)" }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--tint-blue-text)" strokeWidth="2"><circle cx="7.5" cy="15.5" r="5.5"/><path d="M21 2l-9.6 9.6"/><path d="M15.5 7.5l3 3L22 7l-3-3"/></svg>
              </div>
              <div>
                <div className="font-semibold text-sm" style={{ color: "var(--foreground)" }}>초기 설정 · {provisionTarget.hostname}</div>
                <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>hostname/OS 수집 + sudo NOPASSWD 설정을 한 번에 실행합니다.</div>
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>sudo 비밀번호</label>
              <input
                type="password"
                className="input"
                value={sudoPassword}
                onChange={e => setSudoPassword(e.target.value)}
                onKeyDown={e => { if (e.key === "Enter" && !provisioning) submitProvision(); }}
                placeholder="이번 1회만 사용 · 저장되지 않습니다"
                autoFocus
              />
            </div>
            {provisionError && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "var(--tint-red-bg)", color: "var(--tint-red-text)" }}>{provisionError}</div>
            )}
            <div className="flex gap-2 pt-1">
              <button onClick={submitProvision} disabled={provisioning}
                className="btn-primary flex-1 justify-center" style={provisioning ? { opacity: 0.5, cursor: "not-allowed" } : undefined}>
                {provisioning ? "설정 중..." : "실행"}
              </button>
              <button onClick={closeProvision} disabled={provisioning} className="btn-secondary flex-1 justify-center">취소</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
