require 'rails_helper'

RSpec.describe "HelpCenter", type: :request do
  let(:user) { create(:user, :superadmin) }

  before do
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/help"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/help/hotel_admin/onboarding"
      expect(response).to have_http_status(:success)
    end
  end
end
