import urllib.request
import urllib.parse
import json

queries = [
    'vault_core_unsealed',
    'vault_core_response_status_code',
    'sum by (code, type) (rate(vault_core_response_status_code[1m]))',
    'up{job=~".*vault.*"}'
]

for q in queries:
    url = 'http://localhost:9090/api/v1/query?query=' + urllib.parse.quote(q)
    try:
        req = urllib.request.urlopen(url)
        res = json.loads(req.read().decode())
        print(f"Query: {q}")
        print(f"Result: {res['data']['result']}")
    except Exception as e:
        print(f"Error {q}: {e}")
    print("-" * 50)
