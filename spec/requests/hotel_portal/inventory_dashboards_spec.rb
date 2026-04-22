require 'rails_helper'

RSpec.describe "HotelPortal::InventoryDashboards", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    role = create(:role, account: hotel.account)
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "renders rates and inventory overview with hotel-scoped links" do
      create(:room_type, hotel: hotel, name: "Deluxe Room")

      get "/hotel/#{hotel.id}/inventory"

      expect(response).to have_http_status(:success)
    end
  end

  describe "DELETE /public_holidays/:id" do
    it "deletes a saved public holiday rule" do
      holiday_rule = hotel.pricing_rules.create!(
        rule_type: "public_holiday",
        name: "Kaamatan",
        start_date: Date.new(2026, 5, 30),
        end_date: Date.new(2026, 5, 31),
        price: 320
      )

      expect {
        delete destroy_public_holiday_rule_hotel_inventory_dashboards_path(hotel, id: holiday_rule.id)
      }.to change(HotelPricingRule, :count).by(-1)

      expect(response).to redirect_to(hotel_inventory_index_path(hotel))
    end
  end

  describe "DELETE /pricing_tiers/:rule_type" do
    it "deletes a saved general pricing tier rule" do
      create(:room_type, hotel: hotel)
      tier_rule = hotel.pricing_rules.create!(
        rule_type: "general",
        name: "General",
        start_date: Date.new(2026, 5, 1),
        end_date: Date.new(2026, 5, 31),
        price: 120
      )

      expect {
        delete destroy_pricing_tier_rule_hotel_inventory_dashboards_path(hotel, rule_type: "general")
      }.to change(HotelPricingRule, :count).by(-1)

      expect(response).to redirect_to(hotel_inventory_index_path(hotel))
      expect { tier_rule.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "POST /apply_pricing_rules" do
    it "renders inline validation errors for invalid public holiday rows" do
      create(:room_type, hotel: hotel)

      post apply_pricing_rules_hotel_inventory_dashboards_path(hotel), params: {
        pricing_rule: {
          room_type_ids: [ hotel.room_types.first.id ],
          gp_price: "150",
          gp_start_date: "2026-05-20",
          gp_end_date: "2026-06-02",
          public_holidays: [ { name: "", start_date: "", end_date: "", price: "300" } ]
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Public holiday entries must include name, date, and price.")
    end
  end
end
