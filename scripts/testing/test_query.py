import urllib.request
import urllib.parse
import json

query = 'clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status="COMPLETED"}) or sum(ecommerce_orders_total{status="COMPLETED"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)'
url = 'http://127.0.0.1:9090/api/v1/query?query=' + urllib.parse.quote(query)
try:
    with urllib.request.urlopen(url) as resp:
        print("SUCCESS:", resp.read().decode())
except urllib.error.HTTPError as e:
    print("HTTP ERROR:", e.code, e.read().decode())

