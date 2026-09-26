import urllib.request
import urllib.parse
import json

data = urllib.parse.urlencode({
    'client_id': 'microservices_frontend',
    'grant_type': 'password',
    'username': 'admin_user',
    'password': 'admin'
}).encode()

req = urllib.request.Request('http://localhost:8181/realms/microservices-realm/protocol/openid-connect/token', data=data)
try:
    res = urllib.request.urlopen(req)
    token = json.loads(res.read())['access_token']
    print('Keycloak JWT Token acquired successfully.')
except urllib.error.HTTPError as e:
    print('Keycloak HTTP Error:', e.code)
    print('Keycloak Response:', e.read().decode())
    exit(1)

order_req = urllib.request.Request('http://localhost:4200/api/order', headers={'Authorization': f'Bearer {token}'})

try:
    with urllib.request.urlopen(order_req) as r:
        print('Status:', r.status)
        print('Length:', len(json.loads(r.read())))
except urllib.error.HTTPError as e:
    print('HTTPError Code:', e.code)
    print('HTTPError Body:', e.read().decode())
    print('HTTPError Headers:\n', e.headers)
except Exception as ex:
    print('Exception:', ex)
