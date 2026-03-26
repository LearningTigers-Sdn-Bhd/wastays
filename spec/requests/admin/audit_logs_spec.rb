require 'rails_helper'

RSpec.describe "Admin::AuditLogs", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/admin/audit_logs/index"
      expect(response).to have_http_status(:success)
    end
  end

end
