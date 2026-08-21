import { useState } from "react";
import { api, hasAccessToken } from "./api";

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
  const [isLoggedIn, setIsLoggedIn] = useState(hasAccessToken());

  const [page, setPage] = useState<Page>("dashboard");

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

  return (
    <div className="flex h-screen overflow-hidden" style={{ background: "var(--background)" }}>
      <Sidebar current={page} onNavigate={setPage} onLogout={() => {
  void api.logout();
  setIsLoggedIn(false);
}}
 />
      <div className="flex flex-col flex-1 min-w-0">
        <TopBar page={page} />
        <div className="flex-1 overflow-hidden flex flex-col" style={{ background: "var(--background)" }}>
          {renderPage()}
        </div>
      </div>
    </div>
  );
}
