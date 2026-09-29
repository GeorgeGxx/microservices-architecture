import http from 'k6/http';
import { check, sleep } from 'k6';

// Deliberately small local-only baseline. Override BASE_URL to target the
// frontend proxy; requests still pass through Nginx and Apollo Router.
const baseUrl = (__ENV.BASE_URL || 'http://127.0.0.1:5173').replace(/\/$/, '');

export const options = {
  vus: 2,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  const response = http.post(
    `${baseUrl}/graphql`,
    JSON.stringify({ query: '{ __typename }' }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '5s' },
  );

  check(response, {
    'GraphQL responds successfully': (r) => r.status === 200,
    'GraphQL response has data': (r) => {
      try {
        return Boolean(JSON.parse(r.body).data?.__typename);
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
