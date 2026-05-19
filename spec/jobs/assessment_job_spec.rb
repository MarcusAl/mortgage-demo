require "rails_helper"

RSpec.describe AssessmentJob, type: :job do
  let(:user) { create(:user) }
  let(:mortgage_application) { create(:mortgage_application, user: user) }

  describe "#perform" do
    it "calculates assessment and marks as completed" do
      assessment = create(:assessment, mortgage_application: mortgage_application, status: :pending)

      described_class.perform_now(mortgage_application.id)
      assessment.reload

      expect(assessment).to be_completed
      expect(assessment.decision).to be_present
    end

    it "marks assessment as failed on RecordInvalid" do
      assessment = create(:assessment, mortgage_application: mortgage_application, status: :pending)
      allow(Assessments::Calculator).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

      described_class.perform_now(mortgage_application.id)
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
