require 'rails_helper'

RSpec.describe "Admin::Reconciliations", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/reconciliations/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/admin/reconciliations/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /retry_confirmation" do
    it "returns http success" do
      get "/admin/reconciliations/retry_confirmation"
      expect(response).to have_http_status(:success)
    end
  end

end
