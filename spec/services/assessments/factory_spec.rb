require "rails_helper"

RSpec.describe Assessments::Factory, type: :service do
  let(:user) { create(:user) }
  let(:mortgage_application) { create(:mortgage_application, user: user) }

  describe "#call" do
    it "creates a pending assessment and enqueues a job" do
      expect {
        described_class.new(mortgage_application).call
      }.to change(Assessment, :count).by(1)
        .and have_enqueued_job(AssessmentJob).with(mortgage_application.id)

      expect(mortgage_application.assessment).to be_pending
    end

    it "returns the existing assessment when already completed" do
      existing = create(:assessment, :completed, mortgage_application: mortgage_application)
      result = described_class.new(mortgage_application).call

      expect(result).to eq(existing)
      expect(Assessment.count).to eq(1)
    end

    it "returns the existing assessment when pending" do
      existing = create(:assessment, mortgage_application: mortgage_application, status: :pending)
      result = described_class.new(mortgage_application).call

      expect(result).to eq(existing)
      expect(Assessment.count).to eq(1)
    end

    it "returns the existing assessment when processing" do
      existing = create(:assessment, mortgage_application: mortgage_application, status: :processing)
      result = described_class.new(mortgage_application).call

      expect(result).to eq(existing)
      expect(Assessment.count).to eq(1)
    end

    it "returns existing assessment on race condition (RecordNotUnique)" do
      existing = create(:assessment, mortgage_application: mortgage_application)

      allow(mortgage_application).to receive(:assessment).and_return(nil, existing)
      allow(mortgage_application).to receive_message_chain(:build_assessment, :save!).and_raise(ActiveRecord::RecordNotUnique)

      result = described_class.new(mortgage_application).call
      expect(result).to eq(existing)
    end
  end
end
