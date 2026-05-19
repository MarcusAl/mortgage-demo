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
      create(:mortgage_application, user: create(:user))

      get "/api/v1/mortgage_applications", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].length).to eq(2)
    end
  end

  describe "GET /api/v1/mortgage_applications/:id" do
    it "returns the application with nested assessment when present" do
      mortgage_application = create(:mortgage_application, user: user)
      create(:assessment, :completed, mortgage_application: mortgage_application)

      get "/api/v1/mortgage_applications/#{mortgage_application.id}", headers: headers
      data = response.parsed_body["data"]
      expect(data["assessment"]["decision"]).to eq("approved")
    end

    it "returns null assessment when not assessed" do
      mortgage_application = create(:mortgage_application, user: user)

      get "/api/v1/mortgage_applications/#{mortgage_application.id}", headers: headers
      expect(response.parsed_body["data"]["assessment"]).to be_nil
    end

    it "returns 404 for another user's application" do
      other_app = create(:mortgage_application, user: create(:user))

      get "/api/v1/mortgage_applications/#{other_app.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
