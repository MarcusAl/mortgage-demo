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

1. **Separate Assessment model** — The mortgage application is *input data* (income, expenses, deposit, property value, term). The assessment is *derived output* (LTV, DTI, decision, explanation, max borrowing). Keeping these in separate models enforces single responsibility: the application row never changes after submission, while the assessment progresses through states (`pending → completed | failed`). This also supports reassessment without overwriting historical data.

2. **Service objects for business logic** — `Assessments::Calculator` is a pure computation class (LTV, DTI, max borrowing, decision) with no side effects. `Assessments::Factory` orchestrates the workflow: creates a pending assessment, enqueues the background job, and handles idempotency (returns existing assessment if already created). This separation means the calculator is trivially unit-testable and the factory handles the coordination concerns.

3. **Built-in Rails authentication** — `has_secure_token` on User generates tokens, `authenticate_with_http_token` extracts them from the `Authorization` header. No gems, no JWT, no sessions. All resources are scoped through `current_user` to prevent IDOR vulnerabilities. For a demo this is sufficient; in production I'd use Devise or a proper session/JWT setup depending on client architecture.

### Scaling Consideration

The first thing I'd change is **adding Redis caching for completed assessments**. Once an assessment reaches `completed` status, it never changes — this makes it an ideal cache candidate. A simple `Rails.cache.fetch("assessment:#{id}")` on the show endpoint would eliminate repeated database queries for the most common read path. Combined with the existing `includes(:assessment)` on the list endpoint (which already prevents N+1 queries), this would handle significantly higher read throughput without structural changes. Beyond that, Sidekiq scales horizontally by adding workers, and the database scales with read replicas for GET endpoints.

### Trade-offs

- **Affordability logic is deliberately simple** — three rules (LTV ≤ 95%, DTI ≤ 50%, loan ≤ 4.5× income). Real UK underwriting involves credit checks, stress testing at higher interest rates (FCA MCOB 11.6.18R), and employment verification. The thresholds are grounded in real conventions (Bank of England FPC income multiple, Halifax/Nationwide LTV caps) but the implementation is intentionally minimal.
- **No user registration endpoint** — users are seeded via `rails db:seed`. A registration flow would need rate limiting, email verification, and password hashing — complexity that doesn't demonstrate the core assessment architecture.
- **No pagination** — the list endpoint returns all records. Acceptable for a demo; in production I'd add cursor-based pagination to avoid offset performance degradation at scale.

### Next Steps

- **Pagination** on list endpoints (cursor-based for stable ordering)
- **User registration endpoint** with rate limiting and email verification
- **Webhook notifications** on assessment completion (so clients don't need to poll)
- **API versioning via `Accept` header** rather than URL path, for cleaner evolution
- **Stress-tested interest rate calculations** (edge cases: zero rate, very long terms, boundary values)
