require 'rails_helper'

RSpec.describe "Admin::Reconciliations", type: :request do
  let(:superadmin) { create(:user, :superadmin) }
  let(:webhook_event) { create(:webhook_event) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/admin/reconciliations"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/admin/reconciliations/#{webhook_event.id}"
      expect(response).to have_http_status(:success)
    end
  end
end
