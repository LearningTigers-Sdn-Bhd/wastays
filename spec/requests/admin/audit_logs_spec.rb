require 'rails_helper'
require 'securerandom'

RSpec.describe "Admin::AuditLogs", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Audit Logs #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-audit-logs-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /index" do
    it "renders the audit log page with inline filter actions" do
      get "/admin/audit_logs"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('class="text-2xl font-bold tracking-tight text-foreground sm:text-3xl">Audit Logs')
      expect(response.body).to include("Audit Logs")
      expect(response.body).to include("Review platform activity and operational changes across all hotels.")
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-foreground sm:text-xl">Activity Feed')
      expect(response.body).to include("Activity Feed")
      expect(response.body).to include("All Hotels")
      expect(response.body).to include("All Actions")
      expect(response.body).to include('class="grid w-full gap-4 md:grid-cols-2 xl:grid-cols-[repeat(4,minmax(0,1fr))_auto]"')
      expect(response.body).to include('class="flex items-center gap-3 xl:self-end xl:justify-end"')
      expect(response.body).to include("Apply Filters")
    end

    it "shows old and new values for each audit change" do
      account = create(:account, name: "Sample Hotel Account #{token}")
      hotel = create(:hotel, account: account, name: "Sample Hotel #{token}")
      user = create(:user, account: account, name: "Hotel Owner", email: "hotel-owner-#{token}@example.com")
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
