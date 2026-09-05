import urllib.request
import json

body = {
    'queries': [
        {
            'refId': 'A',
            'datasource': {'type': 'loki', 'uid': 'loki-ds'},
            'expr': '{namespace=~".+"}',
            'queryType': 'range'
        }
    ],
    'from': 'now-15m',
    'to': 'now'
}
data = json.dumps(body).encode('utf-8')
req = urllib.request.Request(
    'http://localhost:30030/api/ds/query',
    data=data,
    headers={
        'Authorization': 'Basic YWRtaW46YWRtaW4=',
        'Content-Type': 'application/json'
    }
)
try:
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        frames = res.get('results', {}).get('A', {}).get('frames', [])
        print('Loki query via Grafana SUCCESS! Frames returned:', len(frames))
except Exception as e:
    print('Loki query error:', e)
