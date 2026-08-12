import http from "k6/http";
import { check, sleep } from "k6";

// Run with: k6 run --env BASE_URL=http://localhost:8080 scripts/load-tests/k6-scenario.js

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

export const options = {
  stages: [
    { duration: "30s", target: 10 },   // ramp up to 10 VUs
    { duration: "2m", target: 10 },    // steady state
    { duration: "30s", target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_duration: ["p(95)<500"],   // 95% of requests < 500ms
    http_req_failed: ["rate<0.05"],     // < 5% failure rate
  },
};

export default function () {
  // List owners
  const owners = http.get(`${BASE_URL}/api/customer/owners`);
  check(owners, { "owners 200": (r) => r.status === 200 });

  // List vets
  const vets = http.get(`${BASE_URL}/api/vet/vets`);
  check(vets, { "vets 200": (r) => r.status === 200 });

  // Get specific owner (if owners exist)
  if (owners.status === 200) {
    const ownerList = owners.json();
    if (ownerList && ownerList.length > 0) {
      const ownerId = ownerList[0].id;
      const owner = http.get(`${BASE_URL}/api/customer/owners/${ownerId}`);
      check(owner, { "owner detail 200": (r) => r.status === 200 });
    }
  }

  sleep(1);
}
