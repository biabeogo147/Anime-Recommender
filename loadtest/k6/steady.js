// Traffic for the canary analysis (stage 5) and the alert drill (stage 6): fake mode, a constant 20 requests per second.
//
// 20 RPS is not chosen to pass the analysis' minimum-traffic guard (even 5 RPS would): it is chosen for the RESOLUTION of
// the success-rate gate. At the 10% step the canary gets about 2 RPS, about 240 requests per two-minute window, where a
// 99% floor tolerates two stray errors; at 60 requests a single error would abort a healthy release (Delivery A5.3).
import { recommend } from './common.js';

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: parseInt(__ENV.RPS || '20', 10),
      timeUnit: '1s',
      duration: __ENV.DURATION || '1h', // the SLO drill (short, as built) runs DURATION=2h30m; the full one of design §4.3 needs 4h (SLO A5.2)
      preAllocatedVUs: 40,
      maxVUs: 200,
    },
  },
};

export default function () {
  recommend();
}
