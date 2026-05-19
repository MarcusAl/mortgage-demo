# Mortgage Application API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Rails API-only backend for managing mortgage applications with affordability assessments, token auth, background processing, and Docker support.

**Architecture:** Three models (User, MortgageApplication, Assessment) with token-based auth. Assessments are triggered via an endpoint, processed async by a Sidekiq job that delegates to a Calculator service. All endpoints scoped to the authenticated user. Consistent `{ data: ... }` / `{ errors: [...] }` response contract.

**Tech Stack:** Rails 8 API-only, PostgreSQL, Redis, Sidekiq, RSpec, factory_bot, shoulda-matchers, Rack::Attack

**Conventions (MUST follow):**
- Explicit `type:` metadata on every spec (`type: :model`, `type: :request`, etc.)
- `shoulda-matchers` for model validation specs
- No mocking internal code — only stub external dependencies
- `:unprocessable_content` not `:unprocessable_entity`
- `{ "data": ... }` for success, `{ "errors": [...] }` for errors (always array, always plural key)
- `head :no_content` for destroy (not in scope but follow if needed)
- Scope all user-owned resources through `current_user`
- Jobs receive IDs, find objects, pass objects to services
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`)
- No Claude Code signature in commits
- No raw SQL or Arel — AR query interface only
- Run `bundle exec rubocop` before committing, fix only changed files

---

### Task 1: Project scaffolding and Gemfile setup

**Files:**
- Create: Rails app via `rails new`
- Modify: `Gemfile`
- Modify: `config/database.yml`

- [ ] **Step 1: Generate Rails API-only app**

Run:
```bash
rails new mortgage-demo --api --database=postgresql --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-active-storage --skip-action-cable --skip-hotwire --skip-jbuilder --skip-test
```

Note: Run this from the parent directory of `mortgage-demo`. If the directory already exists (it does — it has a git repo), Rails will ask to overwrite. Accept overwrites for generated files but keep the existing `.git` directory and `docs/` folder.

- [ ] **Step 2: Update Gemfile**

Add to the `Gemfile`:

```ruby
# Background jobs
gem "sidekiq"

# Rate limiting
gem "rack-attack"

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :test do
  gem "shoulda-matchers"
end
```

- [ ] **Step 3: Bundle install**

Run: `bundle install`

- [ ] **Step 4: Install RSpec**

Run: `rails generate rspec:install`

- [ ] **Step 5: Configure RSpec**

Replace `spec/rails_helper.rb` config block to include:

```ruby
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
end
```

Do NOT add `config.infer_spec_type_from_file_location!` — we use explicit `type:` metadata.

Add shoulda-matchers config at the bottom of `spec/rails_helper.rb`:

```ruby
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

- [ ] **Step 6: Configure database**

Update `config/database.yml` for local development and test databases. Use `mortgage_demo_development` and `mortgage_demo_test`.

- [ ] **Step 7: Create databases**

Run: `rails db:create`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold Rails API app with RSpec, Sidekiq, Rack::Attack"
```

---

### Task 2: Database migrations

**Files:**
- Create: `db/migrate/xxx_create_users.rb`
- Create: `db/migrate/xxx_create_mortgage_applications.rb`
- Create: `db/migrate/xxx_create_assessments.rb`

- [ ] **Step 1: Generate users migration**

Run: `rails generate migration CreateUsers`

Replace migration content:

```ruby
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :api_token, null: false
      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :api_token, unique: true
  end
end
```

- [ ] **Step 2: Generate mortgage_applications migration**

Run: `rails generate migration CreateMortgageApplications`

Replace migration content:

```ruby
class CreateMortgageApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :mortgage_applications do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :annual_income_cents, null: false
      t.integer :monthly_expenses_cents, null: false
      t.integer :deposit_cents, null: false
      t.integer :property_value_cents, null: false
      t.integer :term_years, null: false
      t.timestamps
    end
  end
end
```

- [ ] **Step 3: Generate assessments migration**

Run: `rails generate migration CreateAssessments`

Replace migration content:

```ruby
class CreateAssessments < ActiveRecord::Migration[8.0]
  def change
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
  end
end
```

- [ ] **Step 4: Run migrations**

Run: `rails db:migrate`
Expected: All 3 migrations run successfully, `db/schema.rb` updated.

- [ ] **Step 5: Commit**

```bash
git add db/
git commit -m "feat: add database migrations for users, mortgage_applications, assessments"
```

---

### Task 3: Models, factories, and model specs

**Files:**
- Create: `app/models/user.rb`
- Create: `app/models/mortgage_application.rb`
- Create: `app/models/assessment.rb`
- Create: `spec/models/user_spec.rb`
- Create: `spec/models/mortgage_application_spec.rb`
- Create: `spec/models/assessment_spec.rb`
- Create: `spec/factories/users.rb`
- Create: `spec/factories/mortgage_applications.rb`
- Create: `spec/factories/assessments.rb`

- [ ] **Step 1: Create factories**

Create `spec/factories/users.rb`:

```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
  end
end
```

Create `spec/factories/mortgage_applications.rb`:

```ruby
FactoryBot.define do
  factory :mortgage_application do
    user
    annual_income_cents { 60_000_00 }
    monthly_expenses_cents { 1_500_00 }
    deposit_cents { 50_000_00 }
    property_value_cents { 250_000_00 }
    term_years { 25 }
  end
end
```

Create `spec/factories/assessments.rb`:

```ruby
FactoryBot.define do
  factory :assessment do
    mortgage_application
    status { :pending }

    trait :completed do
      status { :completed }
      decision { :approved }
      ltv { 80.0 }
      dti { 30.0 }
      loan_amount_cents { 200_000_00 }
      max_borrowing_cents { 270_000_00 }
      explanation { "Application approved." }
    end

    trait :failed do
      status { :failed }
    end
  end
end
```

- [ ] **Step 2: Write User model spec**

Create `spec/models/user_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:mortgage_applications).dependent(:destroy) }
  end

  describe "validations" do
    subject { create(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email) }
  end

  describe "api_token" do
    it "generates an api_token on create" do
      user = create(:user)
      expect(user.api_token).to be_present
    end
  end
end
```

- [ ] **Step 3: Write MortgageApplication model spec**

Create `spec/models/mortgage_application_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MortgageApplication, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_one(:assessment).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:annual_income_cents) }
    it { is_expected.to validate_numericality_of(:annual_income_cents).is_greater_than(0) }

    it { is_expected.to validate_presence_of(:monthly_expenses_cents) }
    it { is_expected.to validate_numericality_of(:monthly_expenses_cents).is_greater_than_or_equal_to(0) }

    it { is_expected.to validate_presence_of(:deposit_cents) }
    it { is_expected.to validate_numericality_of(:deposit_cents).is_greater_than_or_equal_to(0) }

    it { is_expected.to validate_presence_of(:property_value_cents) }
    it { is_expected.to validate_numericality_of(:property_value_cents).is_greater_than(0) }

    it { is_expected.to validate_presence_of(:term_years) }
    it { is_expected.to validate_numericality_of(:term_years).only_integer.is_greater_than(0) }
  end

  describe "scopes" do
    let(:user) { create(:user) }

    describe ".assessed" do
      it "returns applications with a completed assessment" do
        assessed_app = create(:mortgage_application, user: user)
        create(:assessment, :completed, mortgage_application: assessed_app)
        create(:mortgage_application, user: user)

        expect(described_class.assessed).to contain_exactly(assessed_app)
      end
    end

    describe ".unassessed" do
      it "returns applications with no assessment" do
        create(:mortgage_application, user: user)
        assessed_app = create(:mortgage_application, user: user)
        create(:assessment, :completed, mortgage_application: assessed_app)

        unassessed = described_class.unassessed
        expect(unassessed.count).to eq(1)
        expect(unassessed).not_to include(assessed_app)
      end
    end
  end
end
```

- [ ] **Step 4: Write Assessment model spec**

Create `spec/models/assessment_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Assessment, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:mortgage_application) }
  end

  describe "validations" do
    subject { create(:assessment) }

    it { is_expected.to validate_uniqueness_of(:mortgage_application_id) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, processing: 1, completed: 2, failed: 3)
    }

    it {
      is_expected.to define_enum_for(:decision)
        .with_values(approved: 0, declined: 1)
    }
  end
end
```

- [ ] **Step 5: Run specs to verify they fail**

Run: `bundle exec rspec spec/models/`
Expected: FAIL — models not yet implemented.

- [ ] **Step 6: Implement User model**

Replace `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_secure_token :api_token
  has_many :mortgage_applications, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
```

- [ ] **Step 7: Implement MortgageApplication model**

Replace `app/models/mortgage_application.rb`:

```ruby
class MortgageApplication < ApplicationRecord
  belongs_to :user
  has_one :assessment, dependent: :destroy

  validates :annual_income_cents, presence: true, numericality: { greater_than: 0 }
  validates :monthly_expenses_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :deposit_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :property_value_cents, presence: true, numericality: { greater_than: 0 }
  validates :term_years, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :assessed, -> { joins(:assessment).where(assessments: { status: :completed }) }
  scope :unassessed, -> { where.missing(:assessment) }
end
```

- [ ] **Step 8: Implement Assessment model**

Replace `app/models/assessment.rb`:

```ruby
class Assessment < ApplicationRecord
  belongs_to :mortgage_application

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  enum :decision, { approved: 0, declined: 1 }

  validates :mortgage_application_id, uniqueness: true
end
```

- [ ] **Step 9: Run model specs**

Run: `bundle exec rspec spec/models/`
Expected: All pass.

- [ ] **Step 10: Commit**

```bash
git add app/models/ spec/models/ spec/factories/
git commit -m "feat: add User, MortgageApplication, Assessment models with specs"
```

---

### Task 4: Assessments::Calculator service (TDD)

**Files:**
- Create: `app/services/assessments/calculator.rb`
- Create: `spec/services/assessments/calculator_spec.rb`

- [ ] **Step 1: Create spec directory**

Run: `mkdir -p spec/services/assessments`

- [ ] **Step 2: Write Calculator spec**

Create `spec/services/assessments/calculator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Assessments::Calculator, type: :service do
  subject(:result) { described_class.new(application).call }

  let(:user) { create(:user) }

  describe "approved application" do
    let(:application) do
      create(:mortgage_application,
        user: user,
        annual_income_cents: 60_000_00,
        monthly_expenses_cents: 1_500_00,
        deposit_cents: 50_000_00,
        property_value_cents: 250_000_00,
        term_years: 25)
    end

    it "returns approved decision" do
      expect(result[:decision]).to eq(:approved)
    end

    it "calculates LTV correctly" do
      expect(result[:ltv]).to eq(80.0)
    end

    it "calculates DTI correctly" do
      expect(result[:dti]).to eq(30.0)
    end

    it "calculates loan amount in cents" do
      expect(result[:loan_amount_cents]).to eq(200_000_00)
    end

    it "calculates max borrowing as 4.5x income in cents" do
      expect(result[:max_borrowing_cents]).to eq(270_000_00)
    end

    it "includes an explanation" do
      expect(result[:explanation]).to include("approved")
    end
  end

  describe "declined — LTV too high" do
    let(:application) do
      create(:mortgage_application,
        user: user,
        annual_income_cents: 60_000_00,
        monthly_expenses_cents: 1_000_00,
        deposit_cents: 1_000_00,
        property_value_cents: 250_000_00,
        term_years: 25)
    end

    it "returns declined decision" do
      expect(result[:decision]).to eq(:declined)
    end

    it "explains LTV exceeds limit" do
      expect(result[:explanation]).to include("LTV")
    end
  end

  describe "declined — DTI too high" do
    let(:application) do
      create(:mortgage_application,
        user: user,
        annual_income_cents: 30_000_00,
        monthly_expenses_cents: 1_500_00,
        deposit_cents: 50_000_00,
        property_value_cents: 250_000_00,
        term_years: 25)
    end

    it "returns declined decision" do
      expect(result[:decision]).to eq(:declined)
    end

    it "explains DTI exceeds limit" do
      expect(result[:explanation]).to include("DTI")
    end
  end

  describe "declined — loan exceeds max borrowing" do
    let(:application) do
      create(:mortgage_application,
        user: user,
        annual_income_cents: 30_000_00,
        monthly_expenses_cents: 500_00,
        deposit_cents: 50_000_00,
        property_value_cents: 250_000_00,
        term_years: 25)
    end

    it "returns declined decision" do
      expect(result[:decision]).to eq(:declined)
    end

    it "explains loan exceeds max borrowing" do
      expect(result[:explanation]).to include("maximum borrowing")
    end
  end

  describe "edge cases" do
    it "approves at exactly 95% LTV" do
      application = create(:mortgage_application,
        user: user,
        annual_income_cents: 200_000_00,
        monthly_expenses_cents: 1_000_00,
        deposit_cents: 10_000_00,
        property_value_cents: 200_000_00,
        term_years: 25)
      result = described_class.new(application).call
      expect(result[:ltv]).to eq(95.0)
      expect(result[:decision]).to eq(:approved)
    end

    it "declines just over 95% LTV" do
      application = create(:mortgage_application,
        user: user,
        annual_income_cents: 200_000_00,
        monthly_expenses_cents: 1_000_00,
        deposit_cents: 9_000_00,
        property_value_cents: 200_000_00,
        term_years: 25)
      result = described_class.new(application).call
      expect(result[:ltv]).to be > 95.0
      expect(result[:decision]).to eq(:declined)
    end

    it "declines zero deposit (100% LTV)" do
      application = create(:mortgage_application,
        user: user,
        annual_income_cents: 200_000_00,
        monthly_expenses_cents: 1_000_00,
        deposit_cents: 0,
        property_value_cents: 200_000_00,
        term_years: 25)
      result = described_class.new(application).call
      expect(result[:decision]).to eq(:declined)
    end

    it "approves zero monthly expenses (0% DTI)" do
      application = create(:mortgage_application,
        user: user,
        annual_income_cents: 200_000_00,
        monthly_expenses_cents: 0,
        deposit_cents: 50_000_00,
        property_value_cents: 200_000_00,
        term_years: 25)
      result = described_class.new(application).call
      expect(result[:dti]).to eq(0.0)
      expect(result[:decision]).to eq(:approved)
    end

    it "lists multiple decline reasons when multiple rules fail" do
      application = create(:mortgage_application,
        user: user,
        annual_income_cents: 20_000_00,
        monthly_expenses_cents: 1_500_00,
        deposit_cents: 1_000_00,
        property_value_cents: 250_000_00,
        term_years: 25)
      result = described_class.new(application).call
      expect(result[:decision]).to eq(:declined)
      expect(result[:explanation]).to include("LTV")
      expect(result[:explanation]).to include("maximum borrowing")
    end
  end
end
```

- [ ] **Step 3: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/assessments/calculator_spec.rb`
Expected: FAIL — `Assessments::Calculator` not defined.

- [ ] **Step 4: Create service directory and implement Calculator**

Run: `mkdir -p app/services/assessments`

Create `app/services/assessments/calculator.rb`:

```ruby
module Assessments
  class Calculator
    MAX_LTV = 95.0
    MAX_DTI = 50.0
    INCOME_MULTIPLE = 4.5

    def initialize(mortgage_application)
      @application = mortgage_application
    end

    def call
      {
        ltv: ltv,
        dti: dti,
        loan_amount_cents: loan_amount_cents,
        max_borrowing_cents: max_borrowing_cents,
        decision: decision,
        explanation: explanation
      }
    end

    private

    def loan_amount_cents
      @application.property_value_cents - @application.deposit_cents
    end

    def ltv
      return 100.0 if @application.property_value_cents.zero?

      (loan_amount_cents.to_f / @application.property_value_cents * 100).round(2)
    end

    def dti
      monthly_income = @application.annual_income_cents / 12.0
      return 0.0 if monthly_income.zero?

      (@application.monthly_expenses_cents.to_f / monthly_income * 100).round(2)
    end

    def max_borrowing_cents
      (@application.annual_income_cents * INCOME_MULTIPLE).to_i
    end

    def decision
      decline_reasons.empty? ? :approved : :declined
    end

    def explanation
      if decline_reasons.empty?
        "Application approved. LTV of #{format("%.2f", ltv)}% is within the #{MAX_LTV.to_i}% limit. " \
          "DTI of #{format("%.2f", dti)}% is within the #{MAX_DTI.to_i}% limit. " \
          "Loan amount is within the maximum borrowing of #{INCOME_MULTIPLE}x annual income."
      else
        "Application declined. #{decline_reasons.join(" ")}"
      end
    end

    def decline_reasons
      @decline_reasons ||= [].tap do |reasons|
        if ltv > MAX_LTV
          reasons << "LTV of #{format("%.2f", ltv)}% exceeds the #{MAX_LTV.to_i}% limit."
        end

        if dti > MAX_DTI
          reasons << "DTI of #{format("%.2f", dti)}% exceeds the #{MAX_DTI.to_i}% limit."
        end

        if loan_amount_cents > max_borrowing_cents
          reasons << "Loan amount exceeds the maximum borrowing of #{INCOME_MULTIPLE}x annual income."
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/assessments/calculator_spec.rb`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/ spec/services/
git commit -m "feat: add Assessments::Calculator with affordability logic"
```

---

### Task 5: Assessments::Factory service (TDD)

**Files:**
- Create: `app/services/assessments/factory.rb`
- Create: `spec/services/assessments/factory_spec.rb`

- [ ] **Step 1: Write Factory spec**

Create `spec/services/assessments/factory_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Assessments::Factory, type: :service do
  let(:user) { create(:user) }
  let(:application) { create(:mortgage_application, user: user) }

  describe "#call" do
    it "creates a pending assessment and enqueues a job" do
      expect {
        described_class.new(application).call
      }.to change(Assessment, :count).by(1)
        .and have_enqueued_job(AssessmentJob).with(application.id)

      expect(application.assessment).to be_pending
    end

    it "returns the existing assessment when already completed" do
      existing = create(:assessment, :completed, mortgage_application: application)
      result = described_class.new(application).call

      expect(result).to eq(existing)
      expect(Assessment.count).to eq(1)
    end

    it "returns the existing assessment when pending" do
      existing = create(:assessment, mortgage_application: application, status: :pending)
      result = described_class.new(application).call

      expect(result).to eq(existing)
      expect(Assessment.count).to eq(1)
    end

    it "returns the existing assessment when processing" do
      existing = create(:assessment, mortgage_application: application, status: :processing)
      result = described_class.new(application).call

      expect(result).to eq(existing)
      expect(Assessment.count).to eq(1)
    end

    it "returns existing assessment on race condition (RecordNotUnique)" do
      existing = create(:assessment, mortgage_application: application)

      allow(application).to receive(:assessment).and_return(nil, existing)
      allow(application).to receive_message_chain(:build_assessment, :save!).and_raise(ActiveRecord::RecordNotUnique)

      result = described_class.new(application).call
      expect(result).to eq(existing)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/assessments/factory_spec.rb`
Expected: FAIL — `Assessments::Factory` not defined.

- [ ] **Step 3: Implement Factory**

Create `app/services/assessments/factory.rb`:

```ruby
module Assessments
  class Factory
    def initialize(mortgage_application)
      @mortgage_application = mortgage_application
    end

    def call
      existing = @mortgage_application.assessment
      return existing if existing

      assessment = @mortgage_application.create_assessment!(status: :pending)
      AssessmentJob.perform_later(@mortgage_application.id)
      assessment
    rescue ActiveRecord::RecordNotUnique
      @mortgage_application.reload_assessment
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/assessments/factory_spec.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/assessments/factory.rb spec/services/assessments/factory_spec.rb
git commit -m "feat: add Assessments::Factory with idempotency and race condition handling"
```

---

### Task 6: AssessmentJob (TDD)

**Files:**
- Create: `app/jobs/assessment_job.rb`
- Create: `spec/jobs/assessment_job_spec.rb`

- [ ] **Step 1: Write job spec**

Create `spec/jobs/assessment_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe AssessmentJob, type: :job do
  let(:user) { create(:user) }
  let(:application) { create(:mortgage_application, user: user) }

  describe "#perform" do
    it "calculates assessment and marks as completed" do
      assessment = create(:assessment, mortgage_application: application, status: :pending)

      described_class.perform_now(application.id)
      assessment.reload

      expect(assessment).to be_completed
      expect(assessment.decision).to be_present
      expect(assessment.ltv).to be_present
      expect(assessment.dti).to be_present
      expect(assessment.loan_amount_cents).to be_present
      expect(assessment.max_borrowing_cents).to be_present
      expect(assessment.explanation).to be_present
    end

    it "marks assessment as failed on RecordInvalid" do
      assessment = create(:assessment, mortgage_application: application, status: :pending)
      allow(Assessments::Calculator).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

      described_class.perform_now(application.id)
      expect(assessment.reload).to be_failed
    end

    it "discards silently when application not found" do
      expect {
        described_class.perform_now(-1)
      }.not_to raise_error
    end
  end

  describe "queue" do
    it "uses the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/jobs/assessment_job_spec.rb`
Expected: FAIL — `AssessmentJob` not defined.

- [ ] **Step 3: Implement AssessmentJob**

Create `app/jobs/assessment_job.rb`:

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

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/jobs/assessment_job_spec.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/assessment_job.rb spec/jobs/assessment_job_spec.rb
git commit -m "feat: add AssessmentJob with retry and error handling"
```

---

### Task 7: Authentication in ApplicationController

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Create: `spec/requests/authentication_spec.rb`

- [ ] **Step 1: Write auth request spec**

Create `spec/requests/authentication_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "unauthenticated requests" do
    it "returns 401 when no token provided" do
      get "/api/v1/mortgage_applications"
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["errors"]).to eq(["Unauthorized"])
    end

    it "returns 401 when invalid token provided" do
      get "/api/v1/mortgage_applications",
        headers: { "Authorization" => "Bearer invalid_token" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

- [ ] **Step 2: Set up routes (needed for auth spec to work)**

Replace `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :mortgage_applications, only: [:create, :index, :show] do
        resource :assessment, only: [:create, :show]
      end
    end
  end
end
```

- [ ] **Step 3: Create placeholder controllers (needed for routes)**

Create `app/controllers/api/v1/mortgage_applications_controller.rb`:

```ruby
module Api
  module V1
    class MortgageApplicationsController < ApplicationController
      def index
        render json: { data: [] }
      end

      def show
        render json: { data: {} }
      end

      def create
        render json: { data: {} }, status: :created
      end
    end
  end
end
```

Create `app/controllers/api/v1/assessments_controller.rb`:

```ruby
module Api
  module V1
    class AssessmentsController < ApplicationController
      def show
        render json: { data: {} }
      end

      def create
        render json: { data: {} }, status: :accepted
      end
    end
  end
end
```

- [ ] **Step 4: Run auth spec to verify it fails**

Run: `bundle exec rspec spec/requests/authentication_spec.rb`
Expected: FAIL — no authentication yet, returns 200 instead of 401.

- [ ] **Step 5: Implement authentication**

Replace `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::API
  before_action :authenticate

  private

  def authenticate
    token = request.headers["Authorization"]&.split(" ")&.last
    @current_user = User.find_by(api_token: token)

    render json: { errors: ["Unauthorized"] }, status: :unauthorized unless @current_user
  end

  def current_user
    @current_user
  end
end
```

- [ ] **Step 6: Run auth spec to verify it passes**

Run: `bundle exec rspec spec/requests/authentication_spec.rb`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/ config/routes.rb spec/requests/authentication_spec.rb
git commit -m "feat: add token authentication in ApplicationController"
```

---

### Task 8: MortgageApplicationsController (TDD)

**Files:**
- Modify: `app/controllers/api/v1/mortgage_applications_controller.rb`
- Create: `spec/requests/api/v1/mortgage_applications_spec.rb`

- [ ] **Step 1: Write request spec**

Create `spec/requests/api/v1/mortgage_applications_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::V1::MortgageApplications", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }

  describe "POST /api/v1/mortgage_applications" do
    let(:valid_params) do
      {
        mortgage_application: {
          annual_income_cents: 60_000_00,
          monthly_expenses_cents: 1_500_00,
          deposit_cents: 50_000_00,
          property_value_cents: 250_000_00,
          term_years: 25
        }
      }
    end

    it "creates an application with valid params" do
      post "/api/v1/mortgage_applications", params: valid_params, headers: headers
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"]["annual_income_cents"]).to eq(60_000_00)
    end

    it "returns 422 with invalid params" do
      invalid_params = { mortgage_application: { annual_income_cents: -1, term_years: 25,
        monthly_expenses_cents: 0, deposit_cents: 0, property_value_cents: 100 } }
      post "/api/v1/mortgage_applications", params: invalid_params, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array)
    end

    it "returns 401 without auth" do
      post "/api/v1/mortgage_applications", params: valid_params
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/mortgage_applications" do
    it "returns only the current user's applications" do
      create_list(:mortgage_application, 2, user: user)
      other_user = create(:user)
      create(:mortgage_application, user: other_user)

      get "/api/v1/mortgage_applications", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].length).to eq(2)
    end

    it "includes assessment_status when assessed" do
      application = create(:mortgage_application, user: user)
      create(:assessment, :completed, mortgage_application: application)

      get "/api/v1/mortgage_applications", headers: headers
      expect(response.parsed_body["data"].first["assessment_status"]).to eq("completed")
    end

    it "returns null assessment_status when not assessed" do
      create(:mortgage_application, user: user)

      get "/api/v1/mortgage_applications", headers: headers
      expect(response.parsed_body["data"].first["assessment_status"]).to be_nil
    end
  end

  describe "GET /api/v1/mortgage_applications/:id" do
    it "returns the application with assessment" do
      application = create(:mortgage_application, user: user)
      create(:assessment, :completed, mortgage_application: application)

      get "/api/v1/mortgage_applications/#{application.id}", headers: headers
      data = response.parsed_body["data"]
      expect(data["assessment"]["decision"]).to eq("approved")
    end

    it "returns the application without assessment" do
      application = create(:mortgage_application, user: user)

      get "/api/v1/mortgage_applications/#{application.id}", headers: headers
      data = response.parsed_body["data"]
      expect(data["assessment"]).to be_nil
    end

    it "returns 404 for another user's application" do
      other_user = create(:user)
      other_app = create(:mortgage_application, user: other_user)

      get "/api/v1/mortgage_applications/#{other_app.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/mortgage_applications_spec.rb`
Expected: FAIL — controller not implemented.

- [ ] **Step 3: Implement MortgageApplicationsController**

Replace `app/controllers/api/v1/mortgage_applications_controller.rb`:

```ruby
module Api
  module V1
    class MortgageApplicationsController < ApplicationController
      before_action :set_application, only: :show

      def index
        applications = current_user.mortgage_applications.includes(:assessment)
        render json: { data: applications.map { |app| index_json(app) } }
      end

      def show
        render json: { data: show_json(@application) }
      end

      def create
        application = current_user.mortgage_applications.new(application_params)

        if application.save
          render json: { data: show_json(application) }, status: :created
        else
          render json: { errors: application.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def set_application
        @application = current_user.mortgage_applications.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { errors: ["Not found"] }, status: :not_found
      end

      def application_params
        params.require(:mortgage_application).permit(
          :annual_income_cents,
          :monthly_expenses_cents,
          :deposit_cents,
          :property_value_cents,
          :term_years
        )
      end

      def index_json(application)
        {
          id: application.id,
          annual_income_cents: application.annual_income_cents,
          monthly_expenses_cents: application.monthly_expenses_cents,
          deposit_cents: application.deposit_cents,
          property_value_cents: application.property_value_cents,
          term_years: application.term_years,
          assessment_status: application.assessment&.status,
          created_at: application.created_at
        }
      end

      def show_json(application)
        {
          id: application.id,
          annual_income_cents: application.annual_income_cents,
          monthly_expenses_cents: application.monthly_expenses_cents,
          deposit_cents: application.deposit_cents,
          property_value_cents: application.property_value_cents,
          term_years: application.term_years,
          created_at: application.created_at,
          assessment: assessment_json(application.assessment)
        }
      end

      def assessment_json(assessment)
        return nil unless assessment

        {
          id: assessment.id,
          status: assessment.status,
          decision: assessment.decision,
          ltv: assessment.ltv,
          dti: assessment.dti,
          loan_amount_cents: assessment.loan_amount_cents,
          max_borrowing_cents: assessment.max_borrowing_cents,
          explanation: assessment.explanation
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/requests/api/v1/mortgage_applications_spec.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/mortgage_applications_controller.rb spec/requests/api/v1/mortgage_applications_spec.rb
git commit -m "feat: add MortgageApplicationsController with create, index, show"
```

---

### Task 9: AssessmentsController (TDD)

**Files:**
- Modify: `app/controllers/api/v1/assessments_controller.rb`
- Create: `spec/requests/api/v1/assessments_spec.rb`

- [ ] **Step 1: Write request spec**

Create `spec/requests/api/v1/assessments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Api::V1::Assessments", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:application) { create(:mortgage_application, user: user) }

  describe "POST /api/v1/mortgage_applications/:id/assessment" do
    it "triggers assessment and returns 202 with pending status" do
      post "/api/v1/mortgage_applications/#{application.id}/assessment", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["data"]["status"]).to eq("pending")
    end

    it "returns existing completed assessment with 200" do
      assessment = create(:assessment, :completed, mortgage_application: application)

      post "/api/v1/mortgage_applications/#{application.id}/assessment", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["id"]).to eq(assessment.id)
      expect(response.parsed_body["data"]["decision"]).to eq("approved")
    end

    it "returns 401 without auth" do
      post "/api/v1/mortgage_applications/#{application.id}/assessment"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 for another user's application" do
      other_user = create(:user)
      other_app = create(:mortgage_application, user: other_user)

      post "/api/v1/mortgage_applications/#{other_app.id}/assessment", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/mortgage_applications/:id/assessment" do
    it "returns the completed assessment" do
      create(:assessment, :completed, mortgage_application: application)

      get "/api/v1/mortgage_applications/#{application.id}/assessment", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["decision"]).to eq("approved")
    end

    it "returns 404 when no assessment exists" do
      get "/api/v1/mortgage_applications/#{application.id}/assessment", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/assessments_spec.rb`
Expected: FAIL — controller not implemented.

- [ ] **Step 3: Implement AssessmentsController**

Replace `app/controllers/api/v1/assessments_controller.rb`:

```ruby
module Api
  module V1
    class AssessmentsController < ApplicationController
      before_action :set_application

      def create
        assessment = Assessments::Factory.new(@application).call

        if assessment.pending?
          render json: { data: assessment_json(assessment) }, status: :accepted
        else
          render json: { data: assessment_json(assessment) }
        end
      end

      def show
        assessment = @application.assessment

        if assessment
          render json: { data: assessment_json(assessment) }
        else
          render json: { errors: ["Not found"] }, status: :not_found
        end
      end

      private

      def set_application
        @application = current_user.mortgage_applications.find(params[:mortgage_application_id])
      rescue ActiveRecord::RecordNotFound
        render json: { errors: ["Not found"] }, status: :not_found
      end

      def assessment_json(assessment)
        {
          id: assessment.id,
          status: assessment.status,
          decision: assessment.decision,
          ltv: assessment.ltv,
          dti: assessment.dti,
          loan_amount_cents: assessment.loan_amount_cents,
          max_borrowing_cents: assessment.max_borrowing_cents,
          explanation: assessment.explanation
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/requests/api/v1/assessments_spec.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/assessments_controller.rb spec/requests/api/v1/assessments_spec.rb
git commit -m "feat: add AssessmentsController with idempotent create and show"
```

---

### Task 10: Rack::Attack and Docker

**Files:**
- Create: `config/initializers/rack_attack.rb`
- Create: `docker-compose.yml`

- [ ] **Step 1: Configure Rack::Attack**

Create `config/initializers/rack_attack.rb`:

```ruby
class Rack::Attack
  throttle("api/authenticated", limit: 60, period: 60) do |request|
    request.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if request.path.start_with?("/api/")
  end
end
```

- [ ] **Step 2: Add Rack::Attack middleware**

Add to `config/application.rb` inside the `Application` class:

```ruby
config.middleware.use Rack::Attack
```

- [ ] **Step 3: Create docker-compose.yml**

Create `docker-compose.yml`:

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  web:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgres://postgres:password@db:5432/mortgage_demo_development
      REDIS_URL: redis://redis:6379/0

  sidekiq:
    build: .
    command: bundle exec sidekiq
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgres://postgres:password@db:5432/mortgage_demo_development
      REDIS_URL: redis://redis:6379/0

volumes:
  postgres_data:
```

- [ ] **Step 4: Configure Sidekiq**

Create `config/initializers/sidekiq.rb`:

```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
```

- [ ] **Step 5: Commit**

```bash
git add config/initializers/rack_attack.rb config/initializers/sidekiq.rb config/application.rb docker-compose.yml
git commit -m "feat: add Rack::Attack rate limiting and Docker setup"
```

---

### Task 11: Seeds and README

**Files:**
- Create: `db/seeds.rb`
- Create: `README.md`

- [ ] **Step 1: Create seed data**

Replace `db/seeds.rb`:

```ruby
user = User.find_or_create_by!(email: "test@example.com")
puts "Test user created:"
puts "  Email: #{user.email}"
puts "  API Token: #{user.api_token}"
```

- [ ] **Step 2: Run seeds**

Run: `rails db:seed`
Expected: Prints test user email and API token.

- [ ] **Step 3: Write README**

Create `README.md` with:

- Project overview
- Setup instructions (with and without Docker)
- How to run the application
- How to run tests
- API endpoints with example curl commands using the seed user's token
- Design decisions section (reference `docs/design-decisions.md` and summarise key points):
  1. Separate Assessment model (input vs output data)
  2. Service objects for business logic (Calculator for computation, Factory for orchestration)
  3. Token auth with `has_secure_token`
- Scaling consideration: first change would be caching completed assessments (immutable data, perfect cache candidate) and moving rate limiting to infrastructure layer
- Trade-offs: kept affordability logic simple (3 rules), no user registration endpoint, no pagination
- Next steps: user registration, pagination, API versioning via headers, webhook notifications when assessment completes, stress-tested interest rate calculations

The README should contain actual curl examples that work with the seed user, e.g.:

```bash
# Create an application
curl -X POST http://localhost:3000/api/v1/mortgage_applications \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mortgage_application":{"annual_income_cents":6000000,"monthly_expenses_cents":150000,"deposit_cents":5000000,"property_value_cents":25000000,"term_years":25}}'

# Trigger assessment
curl -X POST http://localhost:3000/api/v1/mortgage_applications/1/assessment \
  -H "Authorization: Bearer YOUR_TOKEN"

# View assessment
curl http://localhost:3000/api/v1/mortgage_applications/1/assessment \
  -H "Authorization: Bearer YOUR_TOKEN"
```

- [ ] **Step 4: Commit**

```bash
git add db/seeds.rb README.md
git commit -m "docs: add README with setup, API docs, and design decisions"
```

---

### Task 12: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass, 0 failures.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No offenses. If any appear, fix them.

- [ ] **Step 3: Verify routes**

Run: `rails routes`
Expected output should include:
```
api_v1_mortgage_applications     GET    /api/v1/mortgage_applications
                                 POST   /api/v1/mortgage_applications
api_v1_mortgage_application      GET    /api/v1/mortgage_applications/:id
api_v1_mortgage_application_assessment
                                 GET    /api/v1/mortgage_applications/:mortgage_application_id/assessment
                                 POST   /api/v1/mortgage_applications/:mortgage_application_id/assessment
```

- [ ] **Step 4: Manual smoke test**

Run: `rails db:seed && rails server`

Then test with curl:
```bash
TOKEN=$(rails runner "puts User.first.api_token")

# Create application
curl -s -X POST http://localhost:3000/api/v1/mortgage_applications \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mortgage_application":{"annual_income_cents":6000000,"monthly_expenses_cents":150000,"deposit_cents":5000000,"property_value_cents":25000000,"term_years":25}}' | jq

# List applications
curl -s http://localhost:3000/api/v1/mortgage_applications \
  -H "Authorization: Bearer $TOKEN" | jq

# Trigger assessment (note: without Sidekiq running, job won't process. Use perform_now in console for smoke test)
```

- [ ] **Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final cleanup and lint fixes"
```
