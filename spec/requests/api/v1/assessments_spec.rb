require "rails_helper"

RSpec.describe "Api::V1::Assessments", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:mortgage_application) { create(:mortgage_application, user: user) }

  describe "POST /api/v1/mortgage_applications/:id/assessment" do
    it "triggers assessment and returns 202 with pending status" do
      post "/api/v1/mortgage_applications/#{mortgage_application.id}/assessment", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["data"]["status"]).to eq("pending")
    end

    it "returns existing completed assessment with 200" do
      assessment = create(:assessment, :completed, mortgage_application: mortgage_application)

      post "/api/v1/mortgage_applications/#{mortgage_application.id}/assessment", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["id"]).to eq(assessment.id)
      expect(response.parsed_body["data"]["decision"]).to eq("approved")
    end

    it "returns 401 without auth" do
      post "/api/v1/mortgage_applications/#{mortgage_application.id}/assessment"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 for another user's application" do
      other_app = create(:mortgage_application, user: create(:user))

      post "/api/v1/mortgage_applications/#{other_app.id}/assessment", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/mortgage_applications/:id/assessment" do
    it "returns the completed assessment" do
      create(:assessment, :completed, mortgage_application: mortgage_application)

      get "/api/v1/mortgage_applications/#{mortgage_application.id}/assessment", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["decision"]).to eq("approved")
    end

    it "returns 404 when no assessment exists" do
      get "/api/v1/mortgage_applications/#{mortgage_application.id}/assessment", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
