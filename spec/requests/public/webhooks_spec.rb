require 'rails_helper'

RSpec.describe "Public::Webhooks", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/public/webhooks/create"
      expect(response).to have_http_status(:success)
    end
  end

end
