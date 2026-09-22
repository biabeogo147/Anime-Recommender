// Shared by the three scripts: the target and the request every iteration sends.
import http from 'k6/http';
import { check } from 'k6';

// k6 calls the api host directly, through the public ALB — never the UI (design §4.7: that is why api.anime exists).
export const BASE_URL = __ENV.BASE_URL || 'https://api.anime.recruitai.io.vn';

// A handful of real-looking queries, so retrieval and the model see varied input rather than one cached string.
const QUERIES = [
  'school romance with comedy',
  'giant robots and war',
  'a detective story with a twist',
  'slow slice of life in the countryside',
  'space bounty hunters',
  'magic school and friendship',
  'post-apocalyptic survival',
  'sports team underdog story',
];

export function recommend() {
  const q = QUERIES[Math.floor(Math.random() * QUERIES.length)];
  const res = http.post(`${BASE_URL}/recommend`, JSON.stringify({ query: q }), {
    headers: { 'content-type': 'application/json' },
    timeout: '60s',
    tags: { name: 'recommend' }, // one name in k6's output whatever the query
  });
  check(res, { 'status 200': (r) => r.status === 200 });
  return res;
}
