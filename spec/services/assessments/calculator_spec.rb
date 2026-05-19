require "rails_helper"

RSpec.describe Assessments::Calculator, type: :service do
  subject(:result) { described_class.new(mortgage_application).call }

  let(:user) { create(:user) }
  let(:mortgage_application) do
    create(:mortgage_application, user: user, **application_overrides)
  end
  let(:application_overrides) { {} }

  describe "approved application" do
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
    let(:application_overrides) { { deposit_cents: 1_000_00 } }

    it "returns declined decision" do
      expect(result[:decision]).to eq(:declined)
    end

    it "explains LTV exceeds limit" do
      expect(result[:explanation]).to include("LTV")
    end
  end

  describe "declined — DTI too high" do
    let(:application_overrides) { { annual_income_cents: 30_000_00 } }

    it "returns declined decision" do
      expect(result[:decision]).to eq(:declined)
    end

    it "explains DTI exceeds limit" do
      expect(result[:explanation]).to include("DTI")
    end
  end

  describe "declined — loan exceeds max borrowing" do
    let(:application_overrides) { { annual_income_cents: 30_000_00, monthly_expenses_cents: 500_00 } }

    it "returns declined decision" do
      expect(result[:decision]).to eq(:declined)
    end

    it "explains loan exceeds max borrowing" do
      expect(result[:explanation]).to include("maximum borrowing")
    end
  end

  describe "edge cases" do
    let(:application_overrides) { edge_overrides }
    let(:edge_overrides) { {} }

    it "approves at exactly 95% LTV" do
      mortgage_application = create(:mortgage_application,
        user: user, annual_income_cents: 200_000_00, monthly_expenses_cents: 1_000_00,
        deposit_cents: 10_000_00, property_value_cents: 200_000_00, term_years: 25)
      result = described_class.new(mortgage_application).call
      expect(result[:ltv]).to eq(95.0)
      expect(result[:decision]).to eq(:approved)
    end

    it "declines just over 95% LTV" do
      mortgage_application = create(:mortgage_application,
        user: user, annual_income_cents: 200_000_00, monthly_expenses_cents: 1_000_00,
        deposit_cents: 9_000_00, property_value_cents: 200_000_00, term_years: 25)
      result = described_class.new(mortgage_application).call
      expect(result[:ltv]).to be > 95.0
      expect(result[:decision]).to eq(:declined)
    end

    it "declines zero deposit (100% LTV)" do
      mortgage_application = create(:mortgage_application,
        user: user, annual_income_cents: 200_000_00, monthly_expenses_cents: 1_000_00,
        deposit_cents: 0, property_value_cents: 200_000_00, term_years: 25)
      result = described_class.new(mortgage_application).call
      expect(result[:decision]).to eq(:declined)
    end

    it "approves zero monthly expenses (0% DTI)" do
      mortgage_application = create(:mortgage_application,
        user: user, annual_income_cents: 200_000_00, monthly_expenses_cents: 0,
        deposit_cents: 50_000_00, property_value_cents: 200_000_00, term_years: 25)
      result = described_class.new(mortgage_application).call
      expect(result[:dti]).to eq(0.0)
      expect(result[:decision]).to eq(:approved)
    end

    it "lists multiple decline reasons when multiple rules fail" do
      mortgage_application = create(:mortgage_application,
        user: user, annual_income_cents: 20_000_00, monthly_expenses_cents: 1_500_00,
        deposit_cents: 1_000_00, property_value_cents: 250_000_00, term_years: 25)
      result = described_class.new(mortgage_application).call
      expect(result[:decision]).to eq(:declined)
      expect(result[:explanation]).to include("LTV")
      expect(result[:explanation]).to include("maximum borrowing")
    end
  end
end
