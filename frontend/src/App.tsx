import { useState } from "react";
import { api, getToken } from "./api";
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

export default function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(() => !!getToken());
  const [page, setPage] = useState<Page>("dashboard");
  const { servers } = useAuditData();

  const handleLogout = () => {
    api.logout();
    setIsLoggedIn(false);
  };

  if (!isLoggedIn) {
    return <LoginPage onLogin={() => setIsLoggedIn(true)} />;
  }

  const renderPage = () => {
    switch (page) {
      case "dashboard": return <DashboardPage onNavigate={setPage} />;
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
      <Sidebar current={page} onNavigate={setPage} onLogout={handleLogout}
        serverCount={servers.length} onlineCount={onlineCount} pendingRemediation={pendingRemediation} />
      <div className="flex flex-col flex-1 min-w-0">
        <TopBar page={page} onNavigate={setPage} />
        <div className="flex-1 overflow-hidden flex flex-col" style={{ background: "var(--background)" }}>
          {renderPage()}
        </div>
      </div>
    </div>
  );
}
