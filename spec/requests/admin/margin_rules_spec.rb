require 'rails_helper'

RSpec.describe "Admin::MarginRules", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/margin_rules/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/admin/margin_rules/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /destroy" do
    it "returns http success" do
      get "/admin/margin_rules/destroy"
      expect(response).to have_http_status(:success)
    end
  end

end
