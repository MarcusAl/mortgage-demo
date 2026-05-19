# Mortgage Application API

A Rails 8 API for submitting mortgage applications and triggering affordability assessments via background jobs.

## Setup (without Docker)

**Prerequisites:** Ruby 3.x, PostgreSQL, Redis

```bash
bundle install
rails db:create db:migrate db:seed
bundle exec rspec
rails server
```

`rails db:seed` prints a test user email and API token — use that token in the examples below.

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
      "applicant_name": "Jane Smith",
      "income": 80000,
      "loan_amount": 300000,
      "loan_term_years": 25,
      "interest_rate": 4.5,
      "property_value": 375000
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
curl http://localhost:3000/api/v1/mortgage_applications/:id \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Trigger an assessment

```bash
curl -X POST http://localhost:3000/api/v1/mortgage_applications/:id/assessment \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Enqueues a background job. Returns `202 Accepted` immediately.

### View an assessment

```bash
curl http://localhost:3000/api/v1/mortgage_applications/:id/assessment \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Returns the assessment result once the job completes. Status is `pending`, `completed`, or `failed`.

## Design Decisions

Full rationale is in [`docs/design-decisions.md`](docs/design-decisions.md). Key choices:

- **Separate Assessment model** — keeps input data (MortgageApplication) separate from computed output (Assessment)
- **Service objects** — `Assessments::Calculator` handles computation, `Assessments::Factory` orchestrates creation and job dispatch
- **Token auth** — `has_secure_token` on User + `authenticate_with_http_token` in ApplicationController; no sessions, no JWT complexity
- **Presenters** — JSON formatting lives in presenter classes, not controllers or models
- **`params.expect`** — Rails 8 strong parameters API for explicit, safe parameter handling

## Scaling Considerations

- **Immutable completed assessments** — once completed, assessments never change, making them ideal cache candidates (Redis, CDN)
- **Rate limiting** — implemented via Rack::Attack; at scale, move to infrastructure (API gateway, load balancer)
- **Sidekiq** — scales horizontally; add workers or introduce multiple named queues for priority tiers
- **Read replicas** — GET endpoints (`/mortgage_applications`, `/assessment`) can be routed to a read replica at serious scale

## Trade-offs

- **Affordability logic is simple** — three rules (LTV, DTI, monthly payment vs income); real underwriting is more complex
- **No user registration endpoint** — users are seeded; a registration flow would need rate limiting and email verification
- **No pagination** — the list endpoint returns all records; acceptable for a demo, not for production

## Next Steps

- User registration endpoint
- Pagination on list endpoints
- API versioning via `Accept` header (rather than URL path)
- Webhook notifications on assessment completion
- Stress-tested interest rate calculations (edge cases: zero rate, very long terms)
