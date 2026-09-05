import urllib.request
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

def check_metrics():
    url = "http://127.0.0.1:9090/api/v1/label/__name__/values"
    with urllib.request.urlopen(url, timeout=5) as resp:
        all_metrics = json.loads(resp.read().decode()).get("data", [])

    ecom_metrics = [m for m in all_metrics if any(k in m for k in ['ecommerce', 'inventory', 'notification', 'idempotency'])]
    print("Found e-commerce & observability metrics:")
    for m in sorted(ecom_metrics):
        q_url = f"http://127.0.0.1:9090/api/v1/query?query={m}"
        try:
            with urllib.request.urlopen(q_url, timeout=3) as q_resp:
                res = json.loads(q_resp.read().decode()).get("data", {}).get("result", [])
                print(f"  • {m} ({len(res)} series)")
                for r in res[:2]:
                    print(f"      tags: {r.get('metric')}, value: {r.get('value', [0, 0])[1]}")
        except Exception as err:
            print(f"  • {m}: error querying: {err}")

if __name__ == "__main__":
    check_metrics()
