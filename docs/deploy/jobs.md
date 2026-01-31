# Background Jobs (Solid Queue)

## Topology

- **Web**: runs Puma only; accepts requests and enqueues jobs.
- **Worker**: dedicated Solid Queue process running `bin/rails solid_queue:start`; executes jobs and recurring tasks.
- **Redis**: required for caching, rate limiting, and job smoke tests.

## Scaling Workers

- Add hosts under the `job` role in `config/deploy.yml`.
- Increase worker concurrency with `JOB_CONCURRENCY` as needed.
- Keep web and worker deploys in sync.
- If you increase `JOB_CONCURRENCY`, ensure the queue database pool size can support it.

## Preflight Checks

- `bin/rails jobs:preflight` verifies:
  - Active Job adapter
  - Redis reachability
  - Queue database connectivity (when configured)
- `bin/rails jobs:smoke` enqueues a job and waits for it to execute.

## Troubleshooting

- **Jobs not running**: ensure the `job` role is deployed and healthy.
- **Redis errors**: check `REDIS_URL` and Redis accessory/container health.
- **Stuck jobs**: confirm worker logs and restart the job service.
- **Queue database errors**: set `QUEUE_DATABASE_URL` (or ensure `DATABASE_URL` is usable for queue).
