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
