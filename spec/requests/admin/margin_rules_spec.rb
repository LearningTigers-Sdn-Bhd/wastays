require 'rails_helper'

RSpec.describe "Admin::MarginRules", type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/admin/margin_rules"
      expect(response).to have_http_status(:success)
    end
  end
end
