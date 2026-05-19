# Design Decisions & Reasoning

Running log of architectural decisions made during planning. Use as interview prep notes.

---

## 1. Model Validations vs PORO Validators

**Decision**: Keep field-level validations on the model.

**Reasoning**: The mortgage application has 5 numeric fields needing presence and numericality checks. This is exactly what `validates :field, presence: true, numericality: { greater_than: 0 }` exists for — declarative, self-documenting, instantly understood by any Rails developer.

**Why not POROs?** POROs for validation make sense when validation logic is complex, spans multiple models, or has conditional business rules that change by context. "Annual income must be a positive number" doesn't qualify. Validations aren't callbacks — they're input guards. They fire on save, return true/false, and don't trigger side effects. No callback hell risk with 5 field-level validations on one model.

**Interview talking point**: "Field validations stay on the model, business rule validation lives in services — that's a clean separation."

---

## 2. Separate Assessment Model vs Enum on Application

**Decision**: Separate `Assessment` model (`has_one :assessment` on MortgageApplication).

**Reasoning**:
- **Single Responsibility**: The mortgage application is *input data* (income, expenses, deposit, property value, term). The assessment is *derived output* (LTV, DTI, decision, explanation, max borrowing). Mixing both on one table means your "application" row is half user-submitted data and half system-generated results.
- **Cleaner domain modelling**: "Show me all declined assessments" is `Assessment.where(decision: :declined)` — the separate model makes the domain explicit.
- **Reassessment**: If you ever need to reassess, you create a new assessment record rather than overwriting columns on the application.
- **Still simple**: One `belongs_to :mortgage_application` with `has_one :assessment`. One extra table, one extra model. The migration is ~15 lines.
- **Idiomatic Rails**: "If you're storing a group of related attributes that represent a distinct concept, that's a model." An assessment with LTV, DTI, decision, explanation, and max_borrowing is a distinct concept.

**Interview talking point**: "I separated input data from derived output. The application is what the user submits, the assessment is what the system produces. This makes the domain boundaries clear and supports reassessment without data loss."

---

## 3. Money Gem vs Integer Cents

**Decision**: Store monetary values as integer cents, no money gem.

**Reasoning**: The fields are all input values for calculations — no currency conversion, no UI display formatting. Storing as integer cents with simple arithmetic keeps the dependency list minimal and is easy to explain. For a technical test, fewer dependencies = less to justify.

**Interview talking point**: "In production I'd reach for the money gem for currency-aware formatting and conversion. Here, integer cents with simple division is sufficient and avoids an unnecessary dependency."

---

## 4. Authentication Approach

**Decision**: Simple token auth using `has_secure_token` on User model.

**Reasoning**: The assignment lists auth as optional. `has_secure_token` is built into Rails, requires no gems, and is sufficient to meaningfully scope resources to users and support rate limiting by user ID. Demonstrates the pattern without over-investing in an optional enhancement.

**Interview talking point**: "I used `has_secure_token` because it's built into Rails and sufficient for a demo. In production I'd use Devise or a proper session/JWT setup depending on the client architecture."

---

## 5. Affordability Logic in Service Objects

**Decision**: Service object (`Assessments::Calculate`) computes LTV, DTI, max borrowing. Separate PORO or service (`Assessments::Decide`) makes the approve/decline decision based on computed values.

**Reasoning**: The calculation is pure business logic — no framework concerns, no side effects. A service object is the natural home. Separating the calculation from the decision means each unit is independently testable and has one clear purpose.

**Interview talking point**: "The calculator computes the numbers, the decider applies the rules. If the business rules change (new LTV threshold, different DTI cap), you change one class. If the calculation formula changes, you change the other."

---

## 6. Background Processing for Assessments

**Decision**: Use a background job for assessment processing with retry logic.

**Reasoning**: The assignment lists this as an optional enhancement. It demonstrates understanding of async processing patterns. The job retries twice for transient errors but not for data validation issues (which require a new application). The assessment model tracks state: `pending -> processing -> completed | failed`.

**Interview talking point**: "Even though the calculation is fast, processing it async demonstrates the pattern you'd use for real underwriting that might call external credit check APIs. The state machine on the assessment model gives the client visibility into progress."

---

## 7. Rate Limiting with Rack::Attack

**Decision**: Add Rack::Attack for rate limiting by user token.

**Reasoning**: Lightweight, well-known middleware. Throttle by authenticated user to prevent abuse. Demonstrates security awareness without over-engineering.

---

## 8. Scoping All Resources to Current User

**Decision**: All endpoints scoped through `current_user` (e.g., `current_user.mortgage_applications.find(params[:id])`).

**Reasoning**: Prevents IDOR vulnerabilities. A user can only access their own applications and assessments. The `current_user` method lives in ApplicationController and is set via the auth before_action.

---

## 9. No Money Gem, No Extra Dependencies

**Decision**: Keep Gemfile minimal — Rails, RSpec, Rack::Attack, Sidekiq (for background jobs), and standard Rails testing gems.

**Reasoning**: Every dependency is a question in the interview. Keep the list short and justifiable.

---

## 10. RESTful Conventions & Thin Controllers

**Decision**: RESTful routes, before_actions for resource loading, controllers delegate to services.

**Reasoning**: Standard Rails patterns. Controllers handle HTTP concerns (params, status codes, response format). Services handle business logic. This is what the assignment means by "appropriate use of Rails conventions."

---

## 11. Scaling Considerations

**What we actually build** (not just talk about):
- Foreign key indexes on `user_id` (mortgage_applications) and `mortgage_application_id` (assessments) — included in migrations from the start
- `includes(:assessment)` on listing endpoints to prevent N+1 queries
- "Already assessed" guard — if an assessment exists, don't create another. Prevents wasted compute from client bugs or retries
- Rack::Attack rate limiting at the application layer

**What we'd change first at scale** (README discussion points):
- **Background jobs are the main bottleneck.** Currently pure math (microseconds), but the pattern exists because real underwriting calls external APIs. Sidekiq scales horizontally — add more workers, use multiple queues to prioritise assessments.
- **Database queries.** With proper indexes and N+1 prevention, the DB is fine for a long time. At serious scale: read replicas for GET endpoints, write primary for POST/PUT. Connection pooling via PgBouncer.
- **Rate limiting.** Rack::Attack works at app layer but at real scale, move to infrastructure (NGINX, Cloudflare, AWS WAF) so bad traffic never hits the app server.
- **Caching.** Assessments are immutable once completed — perfect cache candidate. Add Redis caching on the show endpoint.

**Interview talking point**: "I designed for the scale the assignment needs, but the architecture doesn't paint me into a corner. The separate assessment model, background job pattern, and proper indexing all support horizontal scaling without structural changes."

---

## 12. Idempotent Assessment Guard

**Decision**: If a mortgage application already has a completed assessment, the assess endpoint returns the existing assessment rather than creating a new one.

**Reasoning**: Prevents duplicate work. At scale this matters — without it, a client bug or network retry could create thousands of redundant jobs. It's also better UX: the client gets an immediate response instead of waiting for a job that would produce identical results.

**Interview talking point**: "The endpoint is idempotent by design. Requesting an assessment twice returns the same result without recomputation."

---

## 13. Affordability Calculation Logic & Real-World Grounding

**Decision**: Use LTV, DTI, and income multiple with thresholds grounded in real UK lending conventions.

**Formulas**:
- **LTV** = `(property_value - deposit) / property_value * 100`
- **DTI** = `(monthly_expenses / (annual_income / 12)) * 100`
- **Max borrowing** = `annual_income * 4.5`
- **Loan amount** = `property_value - deposit`

**Decision rules**:
- Decline if LTV > 95% (need at least 5% deposit)
- Decline if DTI > 50% (spending more than half gross monthly income)
- Decline if loan amount > max borrowing (4.5x income cap)
- Approve otherwise

**Real-world basis**:

The 4.5x income multiple comes from the Bank of England FPC rule that limits lenders to no more than 15% of new residential lending at 4.5x+ LTI per quarter. In practice, most high-street lenders cap the majority of applications at 4.5x, with higher multiples reserved for strong credit profiles.
- FCA Guidance: https://www.fca.org.uk/publication/guidance-consultation/gc16-08.pdf
- Explainer: https://www.foxdavidson.co.uk/2026/04/09/uk-mortgage-affordability-rules-guide/
- Income multiples guide: https://www.propertypassport.uk/guides/mortgage-income-multiples-explained

The 95% LTV cap reflects real UK lending products. Halifax caps at £570k loan, Nationwide at £750k. Most mainstream products are 85-90% LTV; 95% is the practical ceiling.
- Halifax 95% mortgages: https://www.halifax.co.uk/mortgages/government-housing-schemes/95-percent-mortgages.html
- Nationwide 95% mortgages: https://www.nationwide.co.uk/mortgages/95-percent

The DTI check is a simplification of the FCA MCOB 11.6.18R stress testing requirement, which requires lenders to assess affordability against future rate rises for a minimum of 5 years. Real lenders stress-test at 6-8% rates. Our 50% DTI cap captures the same intent: does this person have enough headroom?
- FCA stress test rule: https://www.fca.org.uk/firms/interest-rate-stress-test-rule
- FCA mortgage rule review: https://www.fca.org.uk/firms/mortgage-rule-review

**Interview talking point**: "The 4.5x income multiple mirrors the Bank of England's FPC loan-to-income flow limit that most UK lenders follow. The 95% LTV cap reflects real lending products from Halifax and Nationwide. The DTI check is a simplified version of the FCA's MCOB stress testing requirement — in reality lenders model payments at a stressed interest rate, but a percentage-based DTI check captures the same intent. The assignment says the logic doesn't need to be realistic, but grounding it in real conventions made the thresholds easier to justify."

---

## 14. Optional Enhancements

**Included**:
- Background processing (Sidekiq) — already part of the architecture for assessments
- Basic authentication (`has_secure_token`) — already decided
- Docker (Dockerfile + docker-compose with Postgres + Redis) — high impact, low effort, makes the reviewer's "clone and run" walkthrough trivial

**Skipped**:
- Logging/instrumentation — low interview value for the effort. Rails logger is sufficient for a demo. No custom instrumentation or structured logging. If asked: "In production I'd add structured JSON logging and APM (Datadog, New Relic), but for a demo Rails.logger covers debugging needs without adding noise to the codebase."

---

## 15. Standardised API Response Contract

**Decision**: Consistent response envelope across all endpoints.

- **Success**: `{ "data": <object or array> }`
- **Error**: `{ "errors": ["message"] }` — always an array, always plural key
- **Destroy**: `head :no_content` — no body

**Reasoning**: If this were a public API consumed by external developers, a consistent envelope lets them write a generic response handler that always unwraps `data` for success and `errors` for failures — no per-endpoint special casing. This is the same pattern used by Stripe, GitHub, and JSON:API, just lighter weight. It also matches the contract used in other projects in the portfolio.

**Interview talking point**: "I designed the response contract as if this were a public API. Consistent shapes reduce integration effort for consumers. Errors are always an array so the client doesn't need to check if it's a string or array."

---

## 16. Plain Service Classes, No ApplicationService Base

**Decision**: Use plain Ruby classes with explicit `new(...).call` instead of an `ApplicationService` base class.

**Reasoning**: With only 2-3 services, a base class that delegates `.call` to `new.call` is syntactic sugar that adds an inheritance hierarchy without payoff. Plain classes are more transparent and more standard Ruby. The pattern isn't a Rails convention — it's a community pattern.

**Interview talking point**: "For a small service layer I prefer explicit instantiation — it's clearer what's happening. In a larger codebase with dozens of services, I'd add a base class to enforce a consistent interface and reduce boilerplate. It's a scaling decision, not a quality one."

---

## 17. Test Strategy

**Decision**: Model specs, service specs, request specs, job spec. No controller specs, no routing specs.

**Coverage**:
- **Model specs**: Validations (presence, numericality via shoulda-matchers), associations
- **Service specs**: `Assessments::Calculate` — bulk of the tests. Approved scenarios, declined for each rule (LTV too high, DTI too high, loan exceeds max borrowing), edge cases at thresholds
- **Request specs**: Full integration — create application, retrieve, trigger assessment, retrieve assessment. Covers auth, user scoping, idempotency guard, error responses, response contract (`data`/`errors` shape)
- **Job spec**: Verify job finds the record and delegates to service

**Conventions** (from cupbored-app claude.md):
- Explicit `type:` metadata on every spec (e.g., `type: :model`, `type: :request`)
- Factories via factory_bot, `create_list` for bulk creation, no numbered variable names
- `shoulda-matchers` for model validation specs
- No mocking internal code — only stub external dependencies (none in this project)
- `instance_double` for verified doubles if needed
- `:unprocessable_content` not `:unprocessable_entity`

**Interview talking point**: "Request specs test the full stack — params in, JSON out, through auth, controller, service, and database. Service specs test the business logic in isolation with real objects. No mocking internal code means the tests catch real integration issues."

---

## 18. Validation Thresholds — Data Integrity vs Business Rules

**Decision**: Validations guard data integrity, the assessment service applies business rules.

- `annual_income`: > 0 (zero income is nonsensical data)
- `monthly_expenses`: >= 0 (zero expenses is legitimate — no debts)
- `deposit`: >= 0 (zero deposit is valid data; the assessment declines it via LTV check)
- `property_value`: > 0 (zero-value property is nonsensical)
- `term_years`: > 0, integer only

**Reasoning**: A zero deposit isn't invalid *data* — it's a valid application that the assessment will decline. Rejecting it at the validation layer conflates data integrity with business rules. The model says "is this data well-formed?" The service says "does this application qualify?"

**Interview talking point**: "I deliberately separated data integrity validation from business rule evaluation. A zero deposit is valid input — the assessment declines it. This keeps the model focused on data shape and the service focused on business logic."

---

## 19. Unique Index + Validation for Assessment Uniqueness

**Decision**: Both a database unique index and a model uniqueness validation on `mortgage_application_id`.

**Why the validation alone isn't enough**: Two concurrent requests can both pass the validation check before either inserts, creating two assessments for the same application. This is a classic TOCTOU (time-of-check-time-of-use) race condition.

**Why the index alone isn't enough**: The DB raises `ActiveRecord::RecordNotUnique` which gives unfriendly error messages. The validation gives a clean error for normal (non-concurrent) duplicate attempts.

**Why some devs avoid unique indexes** (and why those reasons don't apply here):
- Polymorphic associations make unique indexes awkward — not applicable, simple `belongs_to`
- Soft deletes block new records for the same FK — not applicable, no soft deletes
- NULL handling in multi-column indexes — not applicable, `mortgage_application_id` is `null: false`

**Implementation**:
```ruby
# Model
validates :mortgage_application_id, uniqueness: true

# Migration
add_index :assessments, :mortgage_application_id, unique: true

# Service rescues the race condition
rescue ActiveRecord::RecordNotUnique
  mortgage_application.assessment
```

**Interview talking point**: "The validation handles the normal case with a clean error message. The unique index handles the race condition that validations can't prevent. The service rescues RecordNotUnique and returns the existing assessment — the client never sees an error, they just get the assessment they asked for."

---

## 20. Job Design — Finds MortgageApplication, Not Assessment

**Decision**: `AssessmentJob` receives `mortgage_application_id`, finds the MortgageApplication, accesses the assessment through the association.

**Reasoning**: Follows the convention that jobs find objects by ID and pass them to services. The primary resource being processed is the mortgage application — the assessment is a derived artifact. Finding the application and traversing `application.assessment` is more natural than finding the assessment and traversing back.

---

## 21. Frozen Constants for Business Rule Thresholds

**Decision**: All affordability thresholds defined as frozen constants on the Calculate service.

```ruby
MAX_LTV = 95.0
MAX_DTI = 50.0
INCOME_MULTIPLE = 4.5
```

**Reasoning**: Self-documenting, easy to find, easy to change. Constants make the business rules explicit and testable — you can assert against `Assessments::Calculate::MAX_LTV` in specs rather than magic numbers.

---

## 22. has_secure_token — Model vs Migration Responsibilities

**Decision**: Use the `token` type in the migration generator to get the column + unique index together.

`has_secure_token` (model macro) generates the token value and adds a uniqueness validation. It does **not** create the database index. The migration must add the unique index — either manually or via the `token` type generator which handles both.

**Interview talking point**: "The model validates uniqueness at the application layer, but the DB index is what actually prevents collisions under concurrent writes. I used the `token` migration type so Rails handles both column and index creation."

---

## 23. Service Naming Convention

**Decision**: Noun-based names under a domain namespace. No REST verbs, no `Service` suffix.

- `Assessments::Factory` — produces an Assessment (creates new or returns existing)
- `Assessments::Calculator` — pure computation of affordability metrics

**Why not REST verbs**: `Assessments::Create` reads awkwardly as a class name. Nouns describe what the object *is*, not what action it performs. `Factory` and `Calculator` are well-understood pattern names.

**Why no `Service` suffix**: The files live in `app/services/` — the directory already communicates the role. `FactoryService` is redundant like `UserModel` would be.

**Why namespaced, not flat**: p-api uses flat names (`create_credit_product_service.rb`) because many services sit at the root level and need the full name for clarity. With only 2 services in this project, namespacing under `Assessments::` is cleaner and avoids the redundancy of `Assessments::CreateAssessmentService`.

**Interview talking point**: "I used noun-based names because they describe the object's role — a Factory produces things, a Calculator computes things. The namespace provides the domain context, so the class name doesn't need to repeat it."
