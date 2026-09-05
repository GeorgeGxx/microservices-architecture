import urllib.request
import urllib.parse
import json

def check_dashboard(uid):
    print(f"\n==================== Dashboard: {uid} ====================")
    req = urllib.request.Request(
        f"http://localhost:30030/api/dashboards/uid/{uid}",
        headers={"Authorization": "Basic YWRtaW46YWRtaW4="}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        
    dashboard = data.get("dashboard", {})
    panels = dashboard.get("panels", [])
    
    for p in panels:
        pid = p.get("id")
        title = p.get("title", "").encode("ascii", "ignore").decode("ascii")
        targets = p.get("targets", [])
        
        for t in targets:
            expr = t.get("expr")
            if not expr:
                continue
                
            # Replace dashboard variables with defaults
            test_expr = expr.replace("$service", ".*").replace("$__rate_interval", "1m").replace("$__range", "1h")
            q = urllib.parse.quote(test_expr)
            prom_url = f"http://localhost:9090/api/v1/query?query={q}"
            try:
                with urllib.request.urlopen(prom_url) as presp:
                    pdata = json.loads(presp.read().decode("utf-8"))
                    results = pdata.get("data", {}).get("result", [])
                    print(f"[{pid}] {title}: {len(results)} metrics returned | expr: {expr[:60]}...")
            except Exception as e:
                print(f"[{pid}] {title}: PROM QUERY ERROR ({e}) | expr: {expr[:60]}...")

check_dashboard("business-operations")
check_dashboard("technical-security")
