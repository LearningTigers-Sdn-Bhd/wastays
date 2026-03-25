require 'rails_helper'

RSpec.describe "Hotel::PropertyPolicies", type: :request do
  describe "GET /edit" do
    it "returns http success" do
      get "/hotel/property_policies/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/hotel/property_policies/update"
      expect(response).to have_http_status(:success)
    end
  end

end
