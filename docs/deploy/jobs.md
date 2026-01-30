# Background Jobs (Solid Queue)

## Topology

- **Web**: runs Puma only (no job processing inside web).
- **Worker**: dedicated Solid Queue process running `bin/rails solid_queue:start`.

## Scaling Workers

- Add hosts under the `job` role in `config/deploy.yml`.
- Increase worker concurrency with `JOB_CONCURRENCY` as needed.
- Keep web and worker deploys in sync.

## Preflight Checks

- `bin/rails jobs:preflight` verifies:
  - Active Job adapter
  - Redis reachability
- `bin/rails jobs:smoke` enqueues a job and waits for it to execute.

## Troubleshooting

- **Jobs not running**: ensure the `job` role is deployed and healthy.
- **Redis errors**: check `REDIS_URL` and Redis accessory/container health.
- **Stuck jobs**: confirm worker logs and restart the job service.
