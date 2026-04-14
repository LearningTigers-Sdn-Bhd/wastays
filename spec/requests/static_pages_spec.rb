require 'rails_helper'

RSpec.describe "StaticPages", type: :request do
  describe "GET /" do
    it "returns http success" do
      get "/"
      expect(response).to have_http_status(:success)
    end

    it "does not render the mobile bottom nav on the landing page" do
      get "/"

      expect(response.body).not_to include('text-[10px] font-medium">Account</span>')
      expect(response.body).not_to include('text-[10px] font-medium">Search</span>')
    end
  end

  describe "GET /hotels" do
    it "keeps the mobile bottom nav on other public pages" do
      get "/hotels"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('text-[10px] font-medium">Account</span>')
      expect(response.body).to include('text-[10px] font-medium">Search</span>')
    end
  end
end
