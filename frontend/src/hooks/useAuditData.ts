import { useCallback, useEffect, useState } from "react";
import { api, type Server, type Scan } from "../api";

// 서버 등록/진단 실행/취약점 조치 등 servers를 그대로 나열하는 모든 페이지가
// 여기서 한 번 정렬된 순서를 그대로 받는다 - 온라인(스캔 중 포함)인 서버가
// 위로, 그 다음은 오프라인/오류, 각 그룹 안에서는 호스트명 사전순.
function sortServers(list: Server[]): Server[] {
  const isUp = (s: Server) => s.status === "online" || s.status === "scanning";
  return [...list].sort((a, b) => {
    const ua = isUp(a), ub = isUp(b);
    if (ua !== ub) return ua ? -1 : 1;
    return a.hostname.localeCompare(b.hostname, "ko");
  });
}

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
      setDb(company); setScan(latest); setServers(sortServers(srv));
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
