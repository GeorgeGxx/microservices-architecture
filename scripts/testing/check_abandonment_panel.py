import urllib.request
import urllib.parse
import json

queries = [
    'ecommerce_cart_additions_total',
    'ecommerce_orders_total',
    'ecommerce_orders',
    'sum(ecommerce_cart_additions_total)',
    'sum(ecommerce_orders{status="COMPLETED"})',
    'clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status="COMPLETED"}) or sum(ecommerce_orders_total{status="COMPLETED"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)'
]

for q in queries:
    url = 'http://localhost:9090/api/v1/query?query=' + urllib.parse.quote(q)
    try:
        req = urllib.request.urlopen(url)
        res = json.loads(req.read().decode())
        print(f"Query: {q}")
        print(f"Result: {res['data']['result']}")
    except Exception as e:
        print(f"Query: {q} -> Error: {e}")
    print("-" * 50)
