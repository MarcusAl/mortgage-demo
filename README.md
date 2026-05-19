# Mortgage Application API

A Rails 8 API for submitting mortgage applications and triggering affordability assessments via background jobs.

## Prerequisites

- **Ruby 3.4.8** (check with `ruby -v`; install via [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/))
- **PostgreSQL 14+** (check with `psql --version`)
- **Redis 7+** (check with `redis-cli --version`)

## Setup (without Docker)

```bash
git clone <repo-url> && cd mortgage-demo
bundle install
rails db:create db:migrate db:seed
```

`rails db:seed` prints a test user email and API token — save this token for the API examples below.

### Run the test suite

```bash
bundle exec rspec
```

### Start the server

In separate terminal windows:

```bash
# Terminal 1 — Redis (if not already running)
redis-server

# Terminal 2 — Sidekiq (background jobs)
bundle exec sidekiq

# Terminal 3 — Rails server
rails server
```

The API is now available at `http://localhost:3000`.

## Setup (with Docker)

```bash
docker-compose up --build
docker-compose exec web rails db:create db:migrate db:seed
```

## API Endpoints

All requests require `Authorization: Bearer YOUR_TOKEN` (get yours from `rails db:seed`).

### Create a mortgage application

```bash
curl -X POST http://localhost:3000/api/v1/mortgage_applications \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "mortgage_application": {
      "annual_income_cents": 6000000,
      "monthly_expenses_cents": 150000,
      "deposit_cents": 5000000,
      "property_value_cents": 25000000,
      "term_years": 25
    }
  }'
```

### List mortgage applications

```bash
curl http://localhost:3000/api/v1/mortgage_applications \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Show a mortgage application

```bash
curl http://localhost:3000/api/v1/mortgage_applications/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Trigger an assessment

```bash
curl -X POST http://localhost:3000/api/v1/mortgage_applications/1/assessment \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Enqueues a background job. Returns `202 Accepted` immediately.

### View an assessment

```bash
curl http://localhost:3000/api/v1/mortgage_applications/1/assessment \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Returns the assessment result once the job completes. Status is `pending`, `completed`, or `failed`.

## Design & Reflection

### Key Design Decisions

1. **Idempotent assessment endpoint with race condition handling** — The `POST /assessment` endpoint is idempotent by design: requesting an assessment twice returns the same result without recomputation. This is enforced at three levels — the Factory service checks for an existing assessment, a database unique index on `mortgage_application_id` prevents duplicates under concurrent writes, and the service rescues `ActiveRecord::RecordNotUnique` to return the existing record. The client never sees an error from a retry.

2. **Separation of input data from derived output** — The mortgage application (user-submitted data) and assessment (system-generated result) are separate models. This enforces single responsibility, supports reassessment without overwriting history, and makes the domain boundaries explicit: `Assessment.where(decision: :declined)` reads naturally. The Factory creates a pending assessment synchronously so the client has a resource to poll immediately, while the Calculator runs asynchronously via background job.

3. **Data integrity validations vs business rule evaluation** — Model validations guard data shape (e.g., deposit ≥ 0), while the Calculator service applies business rules (e.g., LTV ≤ 95%). A zero deposit is valid *data* — the assessment declines it. This keeps the model focused on "is this well-formed?" and the service focused on "does this qualify?" The affordability thresholds (4.5× income multiple, 95% LTV, 50% DTI) are grounded in real UK lending conventions (Bank of England FPC rules, FCA MCOB stress testing) and defined as frozen constants for clarity.

### Scaling Consideration

The first thing I'd change is **adding Redis caching for completed assessments**. Once an assessment reaches `completed` status, it never changes — this makes it an ideal cache candidate. A simple `Rails.cache.fetch("assessment:#{id}")` on the show endpoint would eliminate repeated database queries for the most common read path.

The current implementation already includes several scaling foundations: foreign key indexes on all associations, `includes(:assessment)` on listing endpoints to prevent N+1 queries, an idempotency guard that prevents duplicate assessment jobs from client retries, and Rack::Attack rate limiting. Beyond caching, the next steps would be: scaling Sidekiq horizontally with additional workers and priority queues, adding read replicas for GET endpoints (assessments and applications are read-heavy), moving rate limiting to infrastructure (NGINX, API gateway) so bad traffic never reaches the app, and connection pooling via PgBouncer.

### Trade-offs

- **Affordability logic is deliberately simple** — three rules (LTV ≤ 95%, DTI ≤ 50%, loan ≤ 4.5× income). Real UK underwriting involves credit checks, stress testing at higher interest rates (FCA MCOB 11.6.18R), and employment verification. The thresholds are grounded in real conventions (Bank of England FPC income multiple, Halifax/Nationwide LTV caps) but the implementation is intentionally minimal.
- **Integer cents, no money gem** — all monetary values stored as integer cents with simple arithmetic. No currency conversion or display formatting is needed here. In production I'd reach for the money gem for currency-aware operations, but fewer dependencies means less to justify.
- **Plain service classes, no `ApplicationService` base** — with only two services, a base class that delegates `.call` to `new.call` adds an inheritance hierarchy without payoff. In a larger codebase with dozens of services I'd add one for consistency.
- **No user registration endpoint** — users are seeded via `rails db:seed`. A registration flow would need rate limiting, email verification, and password hashing — complexity that doesn't demonstrate the core assessment architecture.
- **No pagination** — the list endpoint returns all records. Acceptable for a demo; in production I'd add cursor-based pagination to avoid offset performance degradation at scale.
- **No custom logging or instrumentation** — Rails logger is sufficient for a demo. In production I'd add structured JSON logging and APM (Datadog, New Relic).

### Next Steps

- **Pagination** on list endpoints (cursor-based for stable ordering)
- **User registration endpoint** with rate limiting and email verification
- **API versioning via `Accept` header** rather than URL path, for cleaner evolution
- **Stress-tested interest rate calculations** (edge cases: zero rate, very long terms, boundary values)
- **Structured JSON logging** and APM integration for production observability
