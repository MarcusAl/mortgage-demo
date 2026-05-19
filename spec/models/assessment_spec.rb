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
