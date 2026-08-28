import { useEffect, useState } from "react";
import { api, getToken, getUsername, setUsername } from "./api";
import { useAuditData } from "./hooks/useAuditData";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import ServersPage from "./pages/ServersPage";
import ScanPage from "./pages/ScanPage";
import ResultsPage from "./pages/ResultsPage";
import RemediationPage from "./pages/RemediationPage";
import ReportsPage from "./pages/ReportsPage";
import SettingsPage from "./pages/SettingsPage";
import Sidebar from "./components/Sidebar";
import TopBar from "./components/TopBar";

type Page = "dashboard" | "servers" | "scan" | "results" | "remediation" | "reports" | "settings";
const PAGES: Page[] = ["dashboard", "servers", "scan", "results", "remediation", "reports", "settings"];

// 상태만으로 페이지를 관리하면(useState) 새로고침할 때마다 React가 처음부터
// 다시 마운트되면서 항상 기본값 "dashboard"(취약점 점검 현황)로 돌아간다 -
// 어느 메뉴에 있었든 새로고침하면 대시보드로 튕기는 문제. URL 해시(#reports 등)에
// 현재 페이지를 같이 실어두면 새로고침해도 브라우저가 그 해시를 그대로 유지해서
// 초기값을 해시에서 복원할 수 있다.
function pageFromHash(): Page {
  const h = location.hash.slice(1) as Page;
  return PAGES.includes(h) ? h : "dashboard";
}

export default function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(() => !!getToken());
  const [page, setPage] = useState<Page>(pageFromHash);
  const { servers } = useAuditData();

  // sa_username은 로그인 응답에서만 채워지는데, 이 토큰이 로그인 절차 없이
  // 그대로 복원된 세션(예: 이 값이 생기기 전부터 남아있던 토큰)이면 비어있을
  // 수 있다 - 사이드바 하단에 ID가 안 보이는 원인. 비어있으면 /api/auth/me로
  // 한 번 채워 넣는다.
  const [username, setUsernameState] = useState(() => getUsername() || "");
  useEffect(() => {
    if (username || !isLoggedIn) return;
    api.me()
      .then(({ username: u }) => {
        setUsername(u);
        setUsernameState(u);
      })
      .catch(() => { /* 세션이 실제로 무효면 다른 API 호출에서 곧 401로 드러난다 */ });
  }, [username, isLoggedIn]);

  const navigate = (p: Page) => {
    setPage(p);
    location.hash = p;
  };

  // 뒤로/앞으로 가기로 해시가 바뀌는 경우(navigate() 밖에서 해시가 바뀌는
  // 유일한 경로)도 page 상태에 반영한다.
  useEffect(() => {
    const onHashChange = () => setPage(pageFromHash());
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  const handleLogout = () => {
    api.logout();
    // 서버 등록 가이드 팝업은 "세션당 1회"인데, 로그아웃도 새 세션의 시작으로
    // 쳐서 다음 로그인 때 다시 뜨게 한다 (ServersPage.tsx GUIDE_SEEN_KEY).
    try { sessionStorage.removeItem("sa_servers_guide_seen"); } catch { /* ignore */ }
    setIsLoggedIn(false);
  };

  if (!isLoggedIn) {
    return <LoginPage onLogin={() => setIsLoggedIn(true)} />;
  }

  const renderPage = () => {
    switch (page) {
      case "dashboard": return <DashboardPage onNavigate={navigate} />;
      case "servers": return <ServersPage />;
      case "scan": return <ScanPage />;
      case "results": return <ResultsPage />;
      case "remediation": return <RemediationPage />;
      case "reports": return <ReportsPage />;
      case "settings": return <SettingsPage />;
    }
  };

  // 사이드바 상태 배너/배지에 쓸 실측값 - servers.length(등록된 전체 서버 수)를
  // 그대로 "연결됨"이라고 보여주면 실제로는 오프라인인 서버까지 연결된 것처럼
  // 보인다. DashboardPage의 onlineServers 계산과 동일한 기준(online/scanning만
  // 연결로 침)을 여기서도 쓴다.
  const onlineCount = servers.filter(s => s.status === "online" || s.status === "scanning").length;
  const pendingRemediation = servers.reduce((a, s) => a + s.failCount, 0);

  return (
    <div className="flex h-screen overflow-hidden" style={{ background: "var(--background)" }}>
      <Sidebar current={page} onNavigate={navigate} onLogout={handleLogout}
        serverCount={servers.length} onlineCount={onlineCount} pendingRemediation={pendingRemediation}
        username={username} />
      <div className="flex flex-col flex-1 min-w-0">
        <TopBar page={page} onNavigate={navigate} />
        <div className="flex-1 overflow-hidden flex flex-col" style={{ background: "var(--background)" }}>
          {renderPage()}
        </div>
      </div>
    </div>
  );
}
