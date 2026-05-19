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
