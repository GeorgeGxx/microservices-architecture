import urllib.request
import urllib.parse
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

queries = [
    'sum(ecommerce_orders{status="COMPLETED"})',
    'sum(ecommerce_orders_total{status="COMPLETED"})',
    'sum(ecommerce_cart_additions_total)',
    'clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status="COMPLETED"}) or sum(ecommerce_orders_total{status="COMPLETED"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)'
]

for q in queries:
    url = 'http://127.0.0.1:9090/api/v1/query?query=' + urllib.parse.quote(q)
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            res = data.get('data', {}).get('result', [])
            val = res[0].get('value', [0, 0])[1] if res else 'NO DATA'
            print(f"{q}\n  -> {val}\n")
    except Exception as e:
        print(f"{q}\n  -> ERROR: {e}\n")
