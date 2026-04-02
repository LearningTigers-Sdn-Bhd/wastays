require 'rails_helper'

RSpec.describe "HotelPortal::AuditLogs", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/#{hotel.id}/audit_logs"
      expect(response).to have_http_status(:success)
    end

    it "shows old and new values for audit changes" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")

      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_inventory_update",
        old_value: { "date" => "2026-04-01", "quantity" => 3, "status" => "open" },
        new_value: { "date" => "2026-04-01", "quantity" => 5, "status" => "closed" },
        metadata: { "start_date" => "2026-04-01", "end_date" => "2026-04-03" }
      )

      get "/hotel/#{hotel.id}/audit_logs"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Value")
      expect(response.body).to include("2026-04-01: Qty 3 / Open -&gt; Qty 5 / Closed")
      expect(response.body).not_to include("Target")
      expect(response.body).not_to include("Dates:")
      expect(response.body).to include("Operation Logs")
    end
  end
end
