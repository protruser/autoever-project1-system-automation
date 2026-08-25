import { useCallback, useEffect, useState } from "react";
import { api, type Server, type Scan } from "../api";

export function useAuditData() {
  const [db, setDb] = useState<string | null>(null);
  const [scan, setScan] = useState<Scan | null>(null);
  const [servers, setServers] = useState<Server[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
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
  }, []);

  useEffect(() => { load(); }, [load]);

  // 조치 실행이나 수동 검토 확정처럼 서버(호스트) 단위 점수를 백엔드에서
  // 재계산시키는 동작 뒤에 호출한다 - servers는 최초 마운트 시 한 번만
  // 가져오므로, 이걸 안 부르면 방금 재계산된 점수가 이 페이지에 머무는 동안
  // 화면에 반영되지 않고 새로고침/재방문 전까지 예전 값으로 보인다.
  const reload = useCallback(() => load(), [load]);

  return { db, scan, servers, loading, error, reload };
}
