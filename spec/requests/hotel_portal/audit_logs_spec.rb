require 'rails_helper'

RSpec.describe "HotelPortal::AuditLogs", type: :request, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, status: 'approved', plan: plan) }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "full_audit_trail"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/#{hotel.id}/audit_logs"

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page).to have_css("[data-slot='report-page'][data-report='operation-logs']")
      expect(page).to have_css(".panel-select-menu select.panel-select-menu__native", count: 2)
      expect(page).to have_no_css("select:not(.panel-select-menu__native)")
      expect(page).to have_css(".panel-date-picker", count: 2)
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Operation audit logs")
      caption = page.find(".panel-page-header__caption")
      expect(caption).to have_text(hotel.name)
      expect(caption).to have_text("All records")
      expect(page).to have_css("select#room_type_id option[value='']", exact_text: "All room types", visible: :all)
      expect(page).to have_css("select#action_type option[value='']", exact_text: "All actions", visible: :all)
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
      expect(response.body).to include("Operation audit logs")
    end

    it "preserves selected filters in controls and export links" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")

      get hotel_audit_logs_path(hotel), params: {
        room_type_id: room_type.id,
        action_type: "bulk_inventory_update",
        start_date: "2026-04-01",
        end_date: "2026-04-03"
      }

      page = Capybara.string(response.body)
      expect(page).to have_select("room_type_id", selected: "Deluxe Twin", visible: :all)
      expect(page).to have_select("action_type", selected: "Bulk inventory update", visible: :all)
      expect(page).to have_css("input#start_date[value='2026-04-01']", visible: :all)
      expect(page).to have_css("input#end_date[value='2026-04-03']", visible: :all)
      caption = page.find(".panel-page-header__caption")
      expect(caption).to have_text(hotel.name)
      expect(caption).to have_text("01 Apr 2026 - 03 Apr 2026")
      %i[csv xlsx pdf].each do |format|
        expect(page).to have_link(
          "Export #{format == :xlsx ? 'Excel' : format.to_s.upcase}",
          href: hotel_audit_logs_path(
            hotel,
            format: format,
            room_type_id: room_type.id,
            action_type: "bulk_inventory_update",
            start_date: "2026-04-01",
            end_date: "2026-04-03"
          )
        )
      end
    end

    it "uses a safe start-only boundary for the caption and results" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_rate_update",
        old_value: { "date" => "2026-03-15", "rate" => 100 },
        new_value: { "date" => "2026-03-15", "rate" => 120 },
        created_at: Time.zone.local(2026, 3, 15, 12)
      )
      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_inventory_update",
        old_value: { "date" => "2026-04-02", "quantity" => 3 },
        new_value: { "date" => "2026-04-02", "quantity" => 5 },
        created_at: Time.zone.local(2026, 4, 2, 12)
      )

      get hotel_audit_logs_path(hotel), params: { start_date: "2026-04-01" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page.find(".panel-page-header__caption")).to have_text("From 01 Apr 2026")
      table = page.find("table.panel-table")
      expect(table).to have_text("Bulk Inventory Update")
      expect(table).to have_no_text("Bulk Rate Update")
    end

    it "uses a safe end-only boundary for the caption and results" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_rate_update",
        old_value: { "date" => "2026-03-15", "rate" => 100 },
        new_value: { "date" => "2026-03-15", "rate" => 120 },
        created_at: Time.zone.local(2026, 3, 15, 12)
      )
      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_inventory_update",
        old_value: { "date" => "2026-04-02", "quantity" => 3 },
        new_value: { "date" => "2026-04-02", "quantity" => 5 },
        created_at: Time.zone.local(2026, 4, 2, 12)
      )

      get hotel_audit_logs_path(hotel), params: { end_date: "2026-03-31" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page.find(".panel-page-header__caption")).to have_text("Through 31 Mar 2026")
      table = page.find("table.panel-table")
      expect(table).to have_text("Bulk Rate Update")
      expect(table).to have_no_text("Bulk Inventory Update")
    end

    it "safely treats invalid date boundaries as all records" do
      get hotel_audit_logs_path(hotel), params: { start_date: "not-a-date", end_date: "also-invalid" }

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:success)
      expect(page.find(".panel-page-header__caption")).to have_text("All records")
    end

    it "exports csv/xlsx/pdf" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      create(
        :inventory_audit_log,
        hotel: hotel,
        room_type: room_type,
        user: user,
        action_type: "bulk_inventory_update",
        old_value: { "date" => "2026-04-01", "quantity" => 3, "status" => "open" },
        new_value: { "date" => "2026-04-01", "quantity" => 5, "status" => "closed" }
      )

      get "/hotel/#{hotel.id}/audit_logs.csv"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("text/csv")

      get "/hotel/#{hotel.id}/audit_logs.xlsx"
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get "/hotel/#{hotel.id}/audit_logs.pdf"
      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
    end
  end
end
