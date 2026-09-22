// Criterion #7: how much the MINIMUM deployment (two pods, no autoscaler) carries — fake mode, a RAMPING ARRIVAL RATE
// over ten minutes.
//
// An open model on purpose. Virtual users that each wait for an answer (a closed model) ask less often as the service
// slows, so the requests a real arrival process would have made during the slow period are never sent and never timed
// — coordinated omission — and the knee looks gentler than it is. Here requests arrive at the set rate regardless; when
// no VU is free to start one, k6 counts a dropped iteration (Load A4.2).
//
// maxVUs follows Little's law with room to spare: VUs in use ≈ rate × latency. At the top rate and a latency grown
// several-fold under queueing, it must not run out — hitting maxVUs drops iterations because of the SCRIPT, which is a
// third possible owner of a plateau besides the pods and the workstation (Load A4.3).
//
// The default top rate sits above the ceiling the thread pool alone sets: 40 worker threads per pod over a fake-mode
// median near 0.8 s is about 50 requests per second per pod, about 100 for two — computed, not measured. A knee below
// that is CPU or something else; a ramp that stops short of it would not find the knee at all.
import { recommend } from './common.js';

const MAX_RPS = parseInt(__ENV.MAX_RPS || '120', 10);

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      stages: [
        { target: Math.round(MAX_RPS * 0.25), duration: '2m' },
        { target: Math.round(MAX_RPS * 0.5), duration: '2m' },
        { target: Math.round(MAX_RPS * 0.75), duration: '2m' },
        { target: MAX_RPS, duration: '2m' },
        // Hold the top, so a knee near it shows as a plateau, not a spike. The scaling run (stage 7) holds longer —
        // HOLD=10m — because a new node takes minutes, and a ramp that ends first never sees one.
        { target: MAX_RPS, duration: __ENV.HOLD || '2m' },
      ],
      preAllocatedVUs: 50,
      maxVUs: parseInt(__ENV.MAX_VUS || '1000', 10),
    },
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'],
};

export default function () {
  recommend();
}
