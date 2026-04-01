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

    it "shows old and new values for each audit change" do
      account = create(:account)
      hotel = create(:hotel, account: account, name: "Sample Hotel")
      user = create(:user, account: account, name: "Hotel Owner")
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")

      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_rate_update",
        old_value: { "date" => "2026-04-01", "price" => 100, "currency" => "MYR" },
        new_value: { "date" => "2026-04-01", "price" => 120, "currency" => "MYR" },
        metadata: { "source" => "bulk_editor" }
      )

      get "/admin/audit_logs"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Value")
      expect(response.body).to include("2026-04-01: MYR 100 -&gt; MYR 120")
    end
  end
end
