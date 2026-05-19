require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "unauthenticated requests" do
    it "returns 401 when no token provided" do
      get "/api/v1/mortgage_applications"
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["errors"]).to eq([ "Unauthorized" ])
    end

    it "returns 401 when invalid token provided" do
      get "/api/v1/mortgage_applications",
        headers: { "Authorization" => "Bearer invalid_token" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
