import http from 'k6/http';
import { check, sleep } from 'k6';

// Configurable via CLI env: k6 run -e TARGET_URL=http://<istio-host> load-test.js
const TARGET_URL = __ENV.TARGET_URL || 'http://localhost:30080';

export const options = {
  stages: [
    { duration: '5s', target: 10 },  // Ramp-up to 10 users
    { duration: '15s', target: 25 }, // Steady state 25 users
    { duration: '5s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete below 500ms
    http_req_failed: ['rate<0.01'],   // Less than 1% errors
  },
};

export default function () {
  // Test Products Service via Istio Ingress
  const res = http.get(`${TARGET_URL}/api/product`);
  check(res, {
    'status is 200 or gateway active': (r) => r.status === 200 || r.status === 404 || r.status === 401,
  });
  sleep(0.5);
}
