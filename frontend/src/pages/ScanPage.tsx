import { useEffect, useState } from "react";
import { api } from "../api";
import { useAuditData } from "../hooks/useAuditData";
import { addNotification } from "../notifications";

type ScanState = "idle" | "running" | "done" | "error" | "aborted";

const LOGS_KEY = "sa_scan_logs";
const STATE_KEY = "sa_scan_state";
const START_KEY = "sa_scan_start";   // 진행률 바 복원용: 스캔 시작 시각(ms)과 대상 대수
const HOSTS_KEY = "sa_scan_hosts";
const SECONDS_PER_HOST = 35;         // 진행률 바 추정 기준: 대상 1대당 평균 진단 소요(초)

// localStorage 변경을 알리는 커스텀 이벤트 - 브라우저 기본 "storage" 이벤트는
// 같은 탭 안에서 자기 자신이 쓴 변경은 감지하지 못한다(스펙상 다른 탭/창에서만
// 발생). 진단 실행 페이지를 벗어났다가 돌아왔을 때, 페이지를 떠나기 전에 보낸
// 요청이 나중에 응답을 받아 localStorage를 갱신해도 지금 떠 있는 화면(재mount된
// 인스턴스)이 그걸 알아채려면 같은 탭 안에서도 감지 가능한 이 이벤트가 필요하다.
const SCAN_SYNC_EVENT = "sa-scan-sync";
const notifyScanSync = () => window.dispatchEvent(new Event(SCAN_SYNC_EVENT));

const readScanState = (): ScanState => (localStorage.getItem(STATE_KEY) as ScanState) || "idle";
const readLogs = (): string[] => {
  try { return JSON.parse(localStorage.getItem(LOGS_KEY) || "[]"); } catch { return []; }
};

export default function ScanPage() {
  const { servers, loading, error } = useAuditData();
  const [selected, setSelected]   = useState<string[]>([]);
  const [scanState, setScanState] = useState<ScanState>(readScanState);
  const [logs, setLogs]           = useState<string[]>(readLogs);

  // 다른 탭("storage" 이벤트)과 같은 탭(커스텀 이벤트) 양쪽에서 localStorage가
  // 바뀌면 화면 상태를 다시 동기화한다. 여기서는 항상 localStorage 값을 그대로
  // 읽어와 반영만 하고 다시 쓰지는 않으므로(addLog/setAndPersistState를 거치지
  // 않음) 이벤트가 무한 반복되지 않는다.
  useEffect(() => {
    const sync = () => {
      setScanState(readScanState());
      setLogs(readLogs());
    };
    window.addEventListener("storage", sync);
    window.addEventListener(SCAN_SYNC_EVENT, sync);
    return () => {
      window.removeEventListener("storage", sync);
      window.removeEventListener(SCAN_SYNC_EVENT, sync);
    };
  }, []);

  const toggleServer = (id: string) => setSelected(p => p.includes(id) ? p.filter(x => x !== id) : [...p, id]);

  const addLog = (msg: string) => {
    const time = new Date().toLocaleTimeString("ko-KR", { timeZone: "Asia/Seoul", hour12: false });
    setLogs(prev => {
      const next = [...prev, `[${time}] ${msg}`];
      localStorage.setItem(LOGS_KEY, JSON.stringify(next));
      return next;
    });
    notifyScanSync();
  };

  const setAndPersistState = (s: ScanState) => {
    setScanState(s);
    localStorage.setItem(STATE_KEY, s);
    notifyScanSync();
  };

  const clearLogs = () => {
    setLogs([]);
    localStorage.removeItem(LOGS_KEY);
    notifyScanSync();
  };

  const [aborting, setAborting] = useState(false);

  // 진행률 바(시간 기반 추정): 진단은 Ansible 원격 실행이라 항목별 실시간 진행을
  // 받아올 수 없어(Ansible이 태스크 출력을 끝까지 버퍼링), 대신 대상 1대당 평균
  // 소요 시간(~35초)을 기준으로 경과 시간에 비례해 채운다. 응답이 오면 100%로
  // 스냅한다. 스캔 자체에는 영향이 없다(순수 화면 표시).
  const [progress, setProgress] = useState(0);       // 0~100
  // 재mount(페이지 이동 후 복귀) 시에도 바가 이어지도록 시작시각/대수는 localStorage에서 복원
  const [scanStart, setScanStart] = useState<number | null>(() => {
    const v = localStorage.getItem(START_KEY); return v ? Number(v) : null;
  });
  const [scanHostCount, setScanHostCount] = useState<number>(() => {
    const v = localStorage.getItem(HOSTS_KEY); return v ? Number(v) : 1;
  });

  useEffect(() => {
    if (scanState !== "running" || scanStart == null) return;
    const totalMs = SECONDS_PER_HOST * 1000 * Math.max(1, scanHostCount);
    const id = setInterval(() => {
      const elapsed = Date.now() - scanStart;
      // 완료 전까지는 최대 95%까지만 차오르게(응답 오면 100%로 마무리)
      const pct = Math.min(95, (elapsed / totalMs) * 100);
      setProgress(pct);
    }, 300);
    return () => clearInterval(id);
  }, [scanState, scanStart, scanHostCount]);

  const startScan = async () => {
    if (selected.length === 0) return;
    const targets = servers.filter(s => selected.includes(s.id));
    const hostnames = [...new Set(targets.map(s => s.hostname))];
    const ips = [...new Set(targets.map(s => s.ip))].join(", ");
    setAndPersistState("running");
    clearLogs();
    setProgress(0);
    const hostCount = hostnames.length || 1;
    const startedAt = Date.now();
    setScanHostCount(hostCount);
    setScanStart(startedAt);
    localStorage.setItem(START_KEY, String(startedAt));
    localStorage.setItem(HOSTS_KEY, String(hostCount));
    addLog(`▶ ${ips} 진단 실행 중 (Ansible playbook, 완료까지 수 분 소요될 수 있음)...`);
    try {
      const result = await api.runScan(hostnames);
      setProgress(100);
      setScanStart(null);
      localStorage.removeItem(START_KEY);
      if (result.aborted) {
        setAndPersistState("aborted");
        addLog("■ 진단이 중단되었습니다.");
        addNotification({ type: "info", title: "진단 중단", body: `${ips} 진단이 사용자 요청으로 중단되었습니다.` });
      } else if (result.success) {
        setAndPersistState("done");
        addLog("✓ 진단 완료. DB에 결과 저장됨 — 결과 탭에서 확인하세요.");
        addNotification({ type: "scan_done", title: "진단 완료", body: `${ips} 진단이 완료됐습니다. 결과 탭에서 확인하세요.` });
      } else {
        setAndPersistState("error");
        addLog("✕ 진단 실패:");
        result.output.split("\n").slice(-20).forEach(line => line.trim() && addLog(`  ${line}`));
        addNotification({ type: "scan_fail", title: "진단 실패", body: `${ips} 진단이 실패했습니다. 로그를 확인하세요.` });
      }
    } catch (e) {
      setScanStart(null);
      localStorage.removeItem(START_KEY);
      setProgress(0);
      setAndPersistState("error");
      const msg = e instanceof Error ? e.message : String(e);
      addLog(`✕ 요청 실패: ${msg}`);
      addNotification({ type: "scan_fail", title: "진단 요청 실패", body: `${ips}: ${msg}` });
    }
  };

  // 진단 자체는 백엔드에서 동기로 돌아가는 요청 하나라, 이 버튼은 그 요청을
  // "취소"하는 게 아니라 실행 중인 ansible-playbook 프로세스를 서버에서 직접
  // 죽여달라고 요청한다. 실제 중단 여부/로그는 위 startScan()의 runScan
  // 응답(aborted: true)으로 반영된다 - 이 버튼은 신호만 보낸다.
  const abortScan = async () => {
    setAborting(true);
    try {
      await api.abortScan();
      addLog("■ 중단 요청을 보냈습니다. 진단이 곧 종료됩니다...");
    } catch (e) {
      addLog(`✕ 중단 요청 실패: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setAborting(false);
    }
  };

  // 진단 실행 중이거나 표시할 로그가 있으면, 서버 목록 로딩(useAuditData가 재마운트
  // 때 loading=true로 재조회)에 화면 전체를 막지 않는다. 이 gate가 로그·진행률까지
  // 가리면 "다른 페이지 갔다 오면 진단 완료될 때까지 로그가 안 보이는" 증상이 생긴다.
  const scanActive = scanState === "running" || logs.length > 0;
  if (loading && !scanActive) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error && !scanActive) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--tint-red-text)" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-5">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Server selection */}
        <div className="card" style={{ padding: 0 }}>
          <div className="flex items-center justify-between px-5 py-4" style={{ borderBottom: "1px solid var(--border)" }}>
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>진단 대상 서버 선택</h2>
            <div className="flex gap-2">
              <button onClick={() => setSelected(servers.map(s => s.id))} className="text-xs px-2 py-1 rounded" style={{ color: "var(--tint-blue-text)", background: "var(--tint-blue-bg)" }}>전체 선택</button>
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
                      <span className="text-sm font-medium" style={{ color: "var(--foreground)" }}>{s.hostname}</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded" style={{ background: "var(--muted)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>{s.group}</span>
                    </div>
                    <div className="text-xs mt-0.5 font-mono" style={{ color: "var(--muted-foreground)" }}>{s.ip}{s.os ? ` · ${s.os}` : ""}</div>
                  </div>
                  <div className="text-xs font-medium" style={{ color: "var(--tint-green-text)" }}>{s.status === "online" ? "온라인" : "오프라인"}</div>
                </div>
              );
            })}
          </div>
          <div className="px-5 py-3" style={{ borderTop: "1px solid var(--border)", background: "var(--muted)" }}>
            <div className="text-xs" style={{ color: "var(--muted-foreground)" }}><span style={{ color: "var(--tint-blue-text)", fontWeight: 600 }}>{selected.length}</span>개 서버 선택됨</div>
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
              {scanState === "aborted" && <span className="badge-warning text-xs px-2 py-1 rounded-full">중단됨</span>}
            </div>

            {scanState === "running" && (
              <div className="space-y-1.5">
                <div className="flex items-center justify-between text-xs" style={{ color: "var(--muted-foreground)" }}>
                  <div className="flex items-center gap-2">
                    <div className="w-3.5 h-3.5 rounded-full border-2 animate-spin" style={{ borderColor: "var(--tint-blue-border)", borderTopColor: "var(--tint-blue-text)" }} />
                    진단 실행 중... (완료까지 기다려주세요)
                  </div>
                  <span className="font-mono font-medium" style={{ color: "var(--tint-blue-text)" }}>{Math.round(progress)}%</span>
                </div>
                <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--muted)" }}>
                  <div className="h-full rounded-full" style={{ width: `${progress}%`, background: "var(--tint-blue-text)", transition: "width 0.3s ease" }} />
                </div>
              </div>
            )}

            <div className="flex gap-3">
              <button onClick={startScan} disabled={selected.length === 0 || scanState === "running"} className="btn-primary"
                style={selected.length === 0 || scanState === "running" ? { opacity: 0.4, cursor: "not-allowed" } : { boxShadow: "0 4px 16px rgba(29,78,216,0.25)" }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polygon points="5,3 19,12 5,21"/></svg>
                진단 실행
              </button>
              {scanState === "running" && (
                <button onClick={abortScan} disabled={aborting} className="btn-danger"
                  style={aborting ? { opacity: 0.6, cursor: "not-allowed" } : undefined}>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><rect x="6" y="6" width="12" height="12" rx="1.5"/></svg>
                  {aborting ? "중단 요청 중..." : "중단"}
                </button>
              )}
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
              color: log.includes("✓") ? "var(--tint-green-text)" : log.includes("▶") ? "var(--tint-blue-text)" : log.includes("✕") ? "var(--tint-red-text)" : log.includes("■") ? "var(--tint-amber-text)" : "var(--text-secondary)"
            }}>{log}</div>
          ))}
        </div>
      </div>
    </div>
  );
}
