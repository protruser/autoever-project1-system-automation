import io
import pandas as pd

def generate_csv(hosts_data):
    records = []
    for h in hosts_data:
        for r in h.get("results", []):
            records.append({
                "Hostname": h.get("hostname"),
                "IP": h.get("ip"),
                "Code": r.get("code"),
                "Category": r.get("category"),
                "Title": r.get("title"),
                "Importance": r.get("importance"),
                "Status": r.get("status"),
                "Target_File": r.get("target_file"),
                "Evidence": r.get("evidence_description"),
                "Guide": r.get("guide")
            })
    df = pd.DataFrame(records)
    output = io.BytesIO()
    df.to_csv(output, index=False, encoding="utf-8-sig")
    return output.getvalue()
