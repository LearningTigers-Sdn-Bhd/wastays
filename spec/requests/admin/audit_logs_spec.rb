require 'rails_helper'

RSpec.describe "Admin::AuditLogs", type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/admin/audit_logs"
      expect(response).to have_http_status(:success)
    end
  end
end
