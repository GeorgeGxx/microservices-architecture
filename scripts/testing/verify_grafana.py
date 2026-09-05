import urllib.request
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

auth = 'Basic YWRtaW46YWRtaW4=' # admin:admin
for uid in ['business-operations', 'technical-security']:
    url = f'http://127.0.0.1:3000/api/dashboards/uid/{uid}'
    req = urllib.request.Request(url, headers={'Authorization': auth})
    with urllib.request.urlopen(req, timeout=3) as resp:
        data = json.loads(resp.read().decode())
        title = data.get('dashboard', {}).get('title')
        panels = len(data.get('dashboard', {}).get('panels', []))
        print(f'[✓] Grafana loaded {uid}: "{title}" with {panels} curated panels.')
