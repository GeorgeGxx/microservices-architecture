import urllib.request
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

url = 'http://127.0.0.1:9090/api/v1/query?query=jvm_memory_used_bytes{area="heap"}'
req = urllib.request.Request(url)
with urllib.request.urlopen(req, timeout=5) as resp:
    data = json.loads(resp.read().decode())
    results = data.get('data', {}).get('result', [])
    print(f"Total series for jvm_memory_used_bytes{{area='heap'}}: {len(results)}")
    for r in results:
        m = r.get('metric', {})
        print(f"  metric labels: {m}")
