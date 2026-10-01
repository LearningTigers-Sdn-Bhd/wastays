require "rails_helper"
require "securerandom"

RSpec.describe "Admin::ActivityLogs", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Admin Activity Logs #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "admin-activity-logs-#{token}@example.com") }
  let(:hotel) { create(:hotel, account: account, name: "Activity Hotel #{token}") }

  before { sign_in_as(superadmin) }

  it "shows old and new values for an inventory change" do
    room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
    create(:inventory_audit_log, hotel: hotel, room_type: room_type, user: superadmin, action_type: "bulk_rate_update",
           old_value: { "date" => "2026-04-01", "price" => 100, "currency" => "MYR" },
           new_value: { "date" => "2026-04-01", "price" => 120, "currency" => "MYR" })

    get "/admin/activity_logs"

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Activity log", "Activity Hotel #{token}", "Deluxe Twin", "2026-04-01: MYR 100 -&gt; MYR 120")
  end

  it "lists booking and folio activity on their tabs" do
    create(:booking_audit_log, hotel: hotel, user: superadmin, action_type: "check_out")
    create(:folio_operation_log, booking: create(:booking, hotel: hotel), actor: superadmin, operation_type: "reopen_folio")

    get "/admin/activity_logs", params: { tab: "bookings" }
    expect(response.body).to include("Checked Out")

    get "/admin/activity_logs", params: { tab: "folios" }
    expect(response.body).to include("Reopen folio")
  end

  it "renders every tab" do
    create(:room_operational_audit_log, hotel: hotel, user: superadmin, room_number: "Z-#{token}")
    create(:financial_audit_event, hotel: hotel, event_type: "folio_closed_for_checkout")

    ActivityLogQuery::TABS.each_key do |tab|
      get "/admin/activity_logs", params: { tab: tab }

      expect(response).to have_http_status(:success)
    end

    get "/admin/activity_logs", params: { tab: "rooms" }
    expect(response.body).to include("Room Z-#{token}", "Dirty -&gt; Ready")
    get "/admin/activity_logs", params: { tab: "financial" }
    expect(response.body).to include("Folio closed for checkout")
  end

  it "filters by hotel" do
    create(:inventory_audit_log, hotel: hotel, user: superadmin, action_type: "rate_update")
    create(:inventory_audit_log, hotel: create(:hotel, account: account, name: "Other Hotel #{token}"), user: superadmin, action_type: "inventory_update")

    get "/admin/activity_logs", params: { hotel_id: hotel.id }

    expect(response.body).to include("Rate Update")
    expect(response.body).not_to include("Inventory Update")
  end

  it "shows the recorded data in a sheet" do
    log = create(:booking_audit_log, hotel: hotel, user: superadmin, new_value: { "status" => "confirmed-#{token}" })

    get "/admin/activity_logs/#{log.id}", params: { tab: "bookings" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("confirmed-#{token}", "Recorded data")
  end

  it "shows an empty state inside the table" do
    get "/admin/activity_logs", params: { q: "no-such-#{token}" }

    expect(response.body).to include("No activity found")
  end

  it "redirects the old audit logs page" do
    get "/admin/audit_logs"

    expect(response).to redirect_to("/admin/activity_logs")
  end
end
