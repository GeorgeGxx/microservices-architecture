import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metric: true application failures (5xx server errors or connection aborts)
const serverErrors = new Rate('server_errors');

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
    http_req_failed: ['rate<0.40'],   // Tolerates expected HTTP 429 rate-limiting from Nginx (20 req/s limit)
    server_errors: ['rate<0.05'],     // 5xx server errors must remain below 5%
  },
};

export default function () {
  // Test Products Service via Ingress / Edge
  const res = http.get(`${TARGET_URL}/api/product`);
  const isOkOrRateLimited = res.status === 200 || res.status === 429;
  
  serverErrors.add(res.status >= 500);

  check(res, {
    'status is 200 or gateway rate-limited (429)': () => isOkOrRateLimited,
  });
  sleep(0.5);
}
