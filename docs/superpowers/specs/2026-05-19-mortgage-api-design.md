# Mortgage Application API — Design Spec

## Goal

Build a Rails API-only backend for managing mortgage applications. Users can submit applications, retrieve them, and trigger affordability assessments. The assessment runs asynchronously and returns LTV, DTI, a decision (approved/declined), max borrowing estimate, and an explanation.

## Scope

- User authentication (simple token auth)
- CRUD for mortgage applications (create, index, show — scoped to authenticated user)
- Affordability assessment (async via background job, idempotent)
- Rate limiting (Rack::Attack)
- Docker support (docker-compose with Postgres + Redis)
- Comprehensive test suite (model, service, request, job specs)

Out of scope: user registration UI, password reset, email verification, logging/instrumentation, frontend.

---

## Models

### User

```ruby
has_secure_token :api_token
has_many :mortgage_applications, dependent: :destroy
```

Fields:
- `email` (string, null: false, unique index)
- `api_token` (string, null: false, unique index — via `token` migration type)

### MortgageApplication

```ruby
belongs_to :user
has_one :assessment, dependent: :destroy
```

Fields:
- `user_id` (references, null: false, foreign_key: true, index via references)
- `annual_income_cents` (integer, null: false)
- `monthly_expenses_cents` (integer, null: false)
- `deposit_cents` (integer, null: false)
- `property_value_cents` (integer, null: false)
- `term_years` (integer, null: false)

Validations:
- `annual_income_cents`: presence, numericality greater_than 0
- `monthly_expenses_cents`: presence, numericality greater_than_or_equal_to 0
- `deposit_cents`: presence, numericality greater_than_or_equal_to 0
- `property_value_cents`: presence, numericality greater_than 0
- `term_years`: presence, numericality greater_than 0, only_integer

Scopes:
- `assessed` — `joins(:assessment).where(assessments: { status: :completed })`
- `unassessed` — `where.missing(:assessment)` (Rails 6.1+ — LEFT OUTER JOIN with NULL check, no raw SQL)

Note: `unassessed` only covers applications with no assessment at all. Applications with a pending/processing/failed assessment are excluded from both scopes — they're in-progress. No raw SQL or Arel throughout — AR query interface only.

### Assessment

```ruby
belongs_to :mortgage_application

enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
enum :decision, { approved: 0, declined: 1 }

validates :mortgage_application_id, uniqueness: true
```

Fields:
- `mortgage_application_id` (references, null: false, foreign_key: true, unique index)
- `ltv` (decimal, precision: 5, scale: 2)
- `dti` (decimal, precision: 5, scale: 2)
- `loan_amount_cents` (integer)
- `max_borrowing_cents` (integer)
- `decision` (integer, default: nil — enum: approved/declined)
- `status` (integer, null: false, default: 0 — enum: pending/processing/completed/failed)
- `explanation` (text)

---

## Database Schema

### Migration: create_users

```ruby
create_table :users do |t|
  t.string :email, null: false
  t.string :api_token, null: false
  t.timestamps
end

add_index :users, :email, unique: true
add_index :users, :api_token, unique: true
```

### Migration: create_mortgage_applications

```ruby
create_table :mortgage_applications do |t|
  t.references :user, null: false, foreign_key: true
  t.integer :annual_income_cents, null: false
  t.integer :monthly_expenses_cents, null: false
  t.integer :deposit_cents, null: false
  t.integer :property_value_cents, null: false
  t.integer :term_years, null: false
  t.timestamps
end
```

### Migration: create_assessments

```ruby
create_table :assessments do |t|
  t.references :mortgage_application, null: false, foreign_key: true, index: { unique: true }
  t.decimal :ltv, precision: 5, scale: 2
  t.decimal :dti, precision: 5, scale: 2
  t.integer :loan_amount_cents
  t.integer :max_borrowing_cents
  t.integer :decision
  t.integer :status, null: false, default: 0
  t.text :explanation
  t.timestamps
end
```

---

## API Endpoints

All endpoints require `Authorization: Bearer <api_token>` header.

Response contract:
- Success: `{ "data": <object or array> }`
- Error: `{ "errors": ["message"] }` (always array, always plural key)
- Destroy: `head :no_content`

### POST /api/v1/mortgage_applications

Create a mortgage application.

Request body:
```json
{
  "mortgage_application": {
    "annual_income_cents": 6000000,
    "monthly_expenses_cents": 150000,
    "deposit_cents": 5000000,
    "property_value_cents": 25000000,
    "term_years": 25
  }
}
```

Success: `201 Created`
```json
{
  "data": {
    "id": 1,
    "annual_income_cents": 6000000,
    "monthly_expenses_cents": 150000,
    "deposit_cents": 5000000,
    "property_value_cents": 25000000,
    "term_years": 25,
    "created_at": "2026-05-19T10:00:00Z"
  }
}
```

Validation failure: `422 Unprocessable Content`
```json
{
  "errors": ["Annual income cents must be greater than 0"]
}
```

### GET /api/v1/mortgage_applications

List authenticated user's applications.

Success: `200 OK`
```json
{
  "data": [
    {
      "id": 1,
      "annual_income_cents": 6000000,
      "monthly_expenses_cents": 150000,
      "deposit_cents": 5000000,
      "property_value_cents": 25000000,
      "term_years": 25,
      "assessment_status": "completed",
      "created_at": "2026-05-19T10:00:00Z"
    }
  ]
}
```

Note: `assessment_status` is a convenience field — null if no assessment, otherwise the assessment's status string.

### GET /api/v1/mortgage_applications/:id

Show a single application with its assessment (if exists).

Success: `200 OK`
```json
{
  "data": {
    "id": 1,
    "annual_income_cents": 6000000,
    "monthly_expenses_cents": 150000,
    "deposit_cents": 5000000,
    "property_value_cents": 25000000,
    "term_years": 25,
    "created_at": "2026-05-19T10:00:00Z",
    "assessment": {
      "id": 1,
      "status": "completed",
      "decision": "approved",
      "ltv": 80.0,
      "dti": 30.0,
      "loan_amount_cents": 20000000,
      "max_borrowing_cents": 27000000,
      "explanation": "Application approved. LTV of 80.00% is within the 95% limit. DTI of 30.00% is within the 50% limit. Loan amount is within the maximum borrowing of 4.5x annual income."
    }
  }
}
```

Assessment is null if not yet triggered. Not found for another user's application: `404 Not Found`.

### POST /api/v1/mortgage_applications/:mortgage_application_id/assessment

Trigger an affordability assessment. Idempotent — if a completed assessment exists, returns it immediately.

Success (new assessment): `202 Accepted`
```json
{
  "data": {
    "id": 1,
    "status": "pending"
  }
}
```

Success (already assessed): `200 OK`
```json
{
  "data": {
    "id": 1,
    "status": "completed",
    "decision": "approved",
    "ltv": 80.0,
    "dti": 30.0,
    "loan_amount_cents": 20000000,
    "max_borrowing_cents": 27000000,
    "explanation": "..."
  }
}
```

Application not found: `404 Not Found`

### GET /api/v1/mortgage_applications/:mortgage_application_id/assessment

View assessment result.

Success: `200 OK` (full assessment object as above)
No assessment yet: `404 Not Found`

---

## Routes

```ruby
namespace :api do
  namespace :v1 do
    resources :mortgage_applications, only: [:create, :index, :show] do
      resource :assessment, only: [:create, :show]
    end
  end
end
```

Singular `resource :assessment` because it's a `has_one` relationship.

---

## Authentication

`ApplicationController`:
- `before_action :authenticate`
- `authenticate` uses Rails built-in `authenticate_with_http_token` to extract bearer token
- Sets `current_user`
- Returns `401 Unauthorized` with `{ "errors": ["Unauthorized"] }` if token invalid/missing

---

## Service Layer

### Assessments::Factory

Orchestrator service. Handles idempotency and job enqueueing.

```
Assessments::Factory.new(mortgage_application).call
```

Logic:
1. If mortgage_application already has a completed assessment, return it
2. If mortgage_application has a pending/processing assessment, return it (job is in flight)
3. Create new Assessment (status: pending)
4. Enqueue AssessmentJob with mortgage_application.id
5. Return the assessment
6. Rescue ActiveRecord::RecordNotUnique — return existing assessment (race condition safety net)

### Assessments::Calculator

Pure computation. No side effects, no DB writes.

```
Assessments::Calculator.new(mortgage_application).call
```

Constants:
```ruby
MAX_LTV = 95.0
MAX_DTI = 50.0
INCOME_MULTIPLE = 4.5
```

Formulas:
- `loan_amount = property_value - deposit`
- `ltv = (loan_amount / property_value) * 100`
- `dti = (monthly_expenses / (annual_income / 12)) * 100`
- `max_borrowing = annual_income * INCOME_MULTIPLE`

Decision rules (evaluated in order, first failure declines):
- Decline if LTV > MAX_LTV (95%)
- Decline if DTI > MAX_DTI (50%)
- Decline if loan_amount > max_borrowing
- Approve otherwise

Returns a hash:
```ruby
{
  ltv: 80.0,
  dti: 30.0,
  loan_amount_cents: 20_000_00,
  max_borrowing_cents: 27_000_00,
  decision: :approved,
  explanation: "Application approved. LTV of 80.00% is within..."
}
```

The explanation is a human-readable string built from which rules passed/failed. Each decline reason is listed.

Note: all monetary calculations convert from cents to pounds internally, results stored back as cents.

---

## Background Job

### AssessmentJob

```ruby
class AssessmentJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::StatementInvalid, attempts: 2, wait: 5.seconds
  discard_on ActiveRecord::RecordNotFound

  def perform(mortgage_application_id)
    application = MortgageApplication.find(mortgage_application_id)
    assessment = application.assessment
    assessment.processing!

    result = Assessments::Calculator.new(application).call
    assessment.update!(result.merge(status: :completed))
  rescue ActiveRecord::StatementInvalid
    assessment&.update(status: :failed) if assessment&.persisted?
    raise
  rescue ActiveRecord::RecordInvalid => e
    assessment&.update(status: :failed) if assessment&.persisted?
    Rails.logger.error("Assessment failed for application #{mortgage_application_id}: #{e.message}")
  end
end
```

- `retry_on ActiveRecord::StatementInvalid` — retries DB connection issues (2 attempts, 5s wait)
- `discard_on ActiveRecord::RecordNotFound` — application deleted before job ran
- `ActiveRecord::RecordInvalid` — data issue, marks as failed, does not retry (retrying won't fix bad data)
- No blanket `rescue StandardError` — only rescue errors we understand and can handle

---

## Rate Limiting

Rack::Attack configured in `config/initializers/rack_attack.rb`:

```ruby
Rack::Attack.throttle("api/authenticated", limit: 60, period: 60) do |request|
  request.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if request.path.start_with?("/api/")
end
```

60 requests per minute per token. Returns `429 Too Many Requests` when exceeded.

---

## File Structure

```
app/
  controllers/
    application_controller.rb
    api/
      v1/
        mortgage_applications_controller.rb
        assessments_controller.rb
  models/
    user.rb
    mortgage_application.rb
    assessment.rb
  services/
    assessments/
      factory.rb
      calculator.rb
  jobs/
    assessment_job.rb

config/
  routes.rb
  initializers/
    rack_attack.rb

db/
  migrate/
    xxx_create_users.rb
    xxx_create_mortgage_applications.rb
    xxx_create_assessments.rb

spec/
  models/
    user_spec.rb
    mortgage_application_spec.rb
    assessment_spec.rb
  services/
    assessments/
      factory_spec.rb
      calculator_spec.rb
  requests/
    api/v1/
      mortgage_applications_spec.rb
      assessments_spec.rb
  jobs/
    assessment_job_spec.rb
  factories/
    users.rb
    mortgage_applications.rb
    assessments.rb

docker-compose.yml
Dockerfile          (generated by Rails)
.dockerignore       (generated by Rails)
```

---

## Testing

All specs use explicit `type:` metadata. Factories via factory_bot. shoulda-matchers for model validations. No mocking of internal code. `:unprocessable_content` for 422 status.

### Model Specs

**user_spec.rb**:
- Validates presence of email
- Validates uniqueness of email
- Association: has_many mortgage_applications

**mortgage_application_spec.rb**:
- Validates presence of all fields
- Validates numericality: annual_income_cents > 0, monthly_expenses_cents >= 0, deposit_cents >= 0, property_value_cents > 0, term_years > 0 (integer only)
- Association: belongs_to user, has_one assessment
- Scopes: assessed, unassessed

**assessment_spec.rb**:
- Validates uniqueness of mortgage_application_id
- Enums: status (pending/processing/completed/failed), decision (approved/declined)
- Association: belongs_to mortgage_application

### Service Specs

**assessments/factory_spec.rb**:
- Returns existing completed assessment (idempotency)
- Returns existing pending/processing assessment (job in flight)
- Creates new assessment and enqueues job when none exists
- Handles race condition (RecordNotUnique)

**assessments/calculator_spec.rb** (bulk of the tests):
- Approves when all criteria met (LTV < 95, DTI < 50, loan < max borrowing)
- Declines when LTV > 95%
- Declines when DTI > 50%
- Declines when loan amount exceeds max borrowing (4.5x income)
- Edge case: exactly at LTV threshold (95.0%) — approved
- Edge case: just over LTV threshold (95.01%) — declined
- Edge case: zero deposit (LTV 100%) — declined
- Edge case: zero monthly expenses (DTI 0%) — approved
- Returns correct explanation text for each scenario
- Multiple decline reasons listed when multiple rules fail
- All monetary values returned as cents

### Request Specs

**mortgage_applications_spec.rb**:
- POST create with valid params returns 201 with data wrapper
- POST create with invalid params returns 422 with errors array
- POST create without auth returns 401
- GET index returns only current user's applications
- GET index does not return other users' applications
- GET show returns application with assessment when present
- GET show returns 404 for another user's application
- Response shapes match contract (data/errors)

**assessments_spec.rb**:
- POST create triggers assessment, returns 202 with pending status
- POST create on already-assessed application returns 200 with existing assessment
- POST create without auth returns 401
- POST create on another user's application returns 404
- GET show returns completed assessment
- GET show returns 404 when no assessment exists

### Job Specs

**assessment_job_spec.rb**:
- Finds mortgage application and calls Calculator
- Updates assessment to completed with results
- Marks assessment as failed on error
- Discards silently when application not found

---

## Docker

`docker-compose.yml` with:
- `db`: Postgres
- `redis`: Redis (for Sidekiq)
- `web`: Rails app (depends on db, redis)
- `sidekiq`: Sidekiq worker (depends on db, redis)

The `Dockerfile` is generated by Rails. We add `docker-compose.yml` for orchestration.

---

## Files Changed

All files are new (greenfield project via `rails new`).

- **Create**: `app/controllers/application_controller.rb` — auth before_action, current_user
- **Create**: `app/controllers/api/v1/mortgage_applications_controller.rb` — create, index, show
- **Create**: `app/controllers/api/v1/assessments_controller.rb` — create, show
- **Create**: `app/models/user.rb` — has_secure_token, associations
- **Create**: `app/models/mortgage_application.rb` — validations, associations, scopes
- **Create**: `app/models/assessment.rb` — enums, uniqueness validation, association
- **Create**: `app/services/assessments/factory.rb` — orchestrator
- **Create**: `app/services/assessments/calculator.rb` — pure computation
- **Create**: `app/jobs/assessment_job.rb` — async assessment processing
- **Create**: `config/routes.rb` — API v1 namespaced routes
- **Create**: `config/initializers/rack_attack.rb` — rate limiting
- **Create**: `db/migrate/xxx_create_users.rb`
- **Create**: `db/migrate/xxx_create_mortgage_applications.rb`
- **Create**: `db/migrate/xxx_create_assessments.rb`
- **Create**: `docker-compose.yml`
- **Create**: All spec and factory files listed in file structure
- **Create**: `db/seeds.rb` — test user with known API token for reviewer walkthrough
- **Create**: `README.md` — setup, run, test instructions, design decisions, scaling, trade-offs
