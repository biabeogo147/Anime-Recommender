// Criterion #6: the latency baseline T is read from — Gemini mode, at whatever rate the free tier allows, for long enough
// that at least 200 requests arrive (the guide checks the server-side count, since a 429 or 503 still counts). Two hundred because a p95 rests on its slowest 5%: over 60 requests that is three
// samples, over 200 it is ten, and one slow call near a bucket boundary can no longer decide which bucket T lands in
// (Load A3.6). The DURATION follows from the count and the rate, not the other way round.
//
// T is NOT read from this script's output. It is read from the server-side histogram the SLI counts, over exactly this
// run's window (Load A3.2); k6's p95 is recorded beside it as what a direct client waits.
import { recommend } from './common.js';

const TARGET = parseInt(__ENV.TARGET_REQUESTS || '200', 10);
const PER_MINUTE = parseInt(__ENV.RATE_PER_MINUTE || '10', 10); // keep under the provider's free-tier limit
const MINUTES = Math.ceil(TARGET / PER_MINUTE) + 1;             // one extra minute, so about TARGET + PER_MINUTE arrive

export const options = {
  scenarios: {
    baseline: {
      // An open model even here: requests arrive at the set rate whether or not earlier ones have answered.
      executor: 'constant-arrival-rate',
      rate: PER_MINUTE,
      timeUnit: '1m',
      duration: `${MINUTES}m`,
      preAllocatedVUs: 5,
      maxVUs: 20,
    },
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'],
};

export default function () {
  recommend();
}
