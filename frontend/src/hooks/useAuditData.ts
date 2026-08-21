import { useEffect, useState } from "react";
import { api, type Server, type Scan } from "../api";

export function useAuditData() {
  const [db, setDb] = useState<string | null>(null);
  const [scan, setScan] = useState<Scan | null>(null);
  const [servers, setServers] = useState<Server[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const companies = await api.companies();
        if (!companies.length) { setError("등록된 회사 DB가 없습니다."); return; }
        const company = companies[0];
        const scans = await api.scans(company);
        if (!scans.length) { setError("진단 회차가 없습니다."); return; }
        const latest = scans[0];
        const srv = await api.servers(company, latest.scan_id);
        setDb(company); setScan(latest); setServers(srv);
      } catch (e) {
        setError(e instanceof Error ? e.message : "데이터를 불러오지 못했습니다.");
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  return { db, scan, servers, loading, error };
}
