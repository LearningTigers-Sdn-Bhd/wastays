require 'rails_helper'

RSpec.describe "Hotel::Reports", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/hotel/reports/index"
      expect(response).to have_http_status(:success)
    end
  end

end
