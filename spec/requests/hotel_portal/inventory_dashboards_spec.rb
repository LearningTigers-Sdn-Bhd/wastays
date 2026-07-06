require 'rails_helper'

RSpec.describe "HotelPortal::InventoryDashboards", type: :request do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:user) { create(:user) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    role = create(:role, account: hotel.account)
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "renders validated tabs and nested breadcrumb labels" do
      get hotel_inventory_index_path(hotel), params: { tab: "advanced", subtab: "overrides" }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_css('[data-tabs-default-tab-value="advanced"]')
      expect(page).to have_css("[data-testid='inventory-calendar-panel']")
      expect(page).to have_css("[data-testid='inventory-advanced-panel']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Pricing")
      expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Availability Overrides")
    end

    it "falls back to the default tab and subtab for unknown parameters" do
      get hotel_inventory_index_path(hotel), params: { tab: "unknown", subtab: "unknown" }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_css('[data-tabs-default-tab-value="calendar"]')
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Rates & Availability")
      expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Pricing Rules")
      expect(page).to have_css("[data-subtabs-breadcrumb-segment].hidden")
    end

    it "preserves inventory state in server-rendered navigation links" do
      room_type = create(:room_type, hotel: hotel)

      get hotel_inventory_index_path(hotel), params: {
        start_date: Date.current,
        view_currencies: [ "MYR" ],
        display_currency: "MYR",
        room_type_id: room_type.id,
        tab: "calendar",
        subtab: "overrides"
      }

      page = Capybara.string(response.body)
      next_link = page.find_link("Next 14 days")
      query = Rack::Utils.parse_nested_query(URI.parse(next_link[:href]).query)

      expect(query).to include(
        "display_currency" => "MYR",
        "room_type_id" => room_type.id.to_s,
        "tab" => "calendar",
        "subtab" => "overrides"
      )
      expect(query["view_currencies"]).to eq([ "MYR" ])
    end

    it "renders the PMS availability calendar by default" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room", quantity: 4)
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 0, status: "closed")

      get "/hotel/#{hotel.id}/inventory", params: { start_date: Date.current.to_s }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_content("Rates & Availability")
      expect(page).to have_css("[data-testid='inventory-calendar-grid']")
      expect(page).to have_button("Sync")
      expect(page).to have_content("Pricing Rules")
      expect(page).to have_content("Availability Overrides")
    end

    it "renders rate rows with room-type filtering in toolbar" do
      deluxe = create(:room_type, hotel: hotel, name: "Deluxe Room", quantity: 4)
      twin = create(:room_type, hotel: hotel, name: "Twin Room", quantity: 2)
      deluxe_plan = create(:rate_plan, room_type: deluxe, name: "Best Available")
      create(:rate_plan, room_type: twin, name: "Non Refundable")
      create(:room_rate, room_type: deluxe, rate_plan: deluxe_plan, date: Date.current, price: 320, currency: "MYR")

      get "/hotel/#{hotel.id}/inventory", params: {
        room_type_id: deluxe.id,
        rate_plan_id: deluxe_plan.id,
        display_currency: "MYR",
        start_date: Date.current.to_s
      }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_css("[data-testid='rate-cell-#{deluxe.id}-#{deluxe_plan.id}-#{Date.current}']", text: "320")
      expect(page).not_to have_css("[data-testid^='rate-cell-#{twin.id}-']")
    end

    it "renders restriction badges in unified rate cells" do
      room_type = create(:room_type, hotel: hotel, name: "Twin Room", base_price: 200)
      rate_plan = create(:rate_plan, room_type: room_type, name: "Best Available")
      create(
        :room_rate,
        room_type: room_type,
        rate_plan: rate_plan,
        date: Date.current,
        price: 250,
        currency: "MYR",
        min_stay: 2,
        max_stay: 5,
        closed_to_arrival: true,
        stop_sell: true
      )

      get "/hotel/#{hotel.id}/inventory", params: { display_currency: "MYR", start_date: Date.current.to_s }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "MIN2")
      expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "MAX5")
      expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "CTA")
      expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "STOP")
    end
  end

  describe "POST /bulk_save_ari" do
    it "preserves active tabs and currency state after saving" do
      room_type = create(:room_type, hotel: hotel, base_price: 180)
      rate_plan = create(:rate_plan, room_type: room_type, name: "Best Available Rate")

      post bulk_save_ari_hotel_inventory_dashboards_path(hotel), params: {
        tab: "calendar",
        subtab: "overrides",
        display_currency: "MYR",
        view_currencies: [ "MYR" ],
        selection_update: {
          mode: "combined",
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          start_date: Date.current.to_s,
          end_date: Date.current.to_s,
          apply_inventory: "0",
          apply_rates: "1",
          apply_restrictions: "0",
          price: "333.00",
          currency: "MYR"
        }
      }

      expect(response).to redirect_to(
        hotel_inventory_index_path(
          hotel,
          start_date: Date.current.to_s,
          view_currencies: [ "MYR" ],
          display_currency: "MYR",
          room_type_id: room_type.id.to_s,
          rate_plan_id: rate_plan.id.to_s,
          tab: "calendar",
          subtab: "overrides"
        )
      )
    end

    it "saves a single-date rate update through the calendar payload" do
      room_type = create(:room_type, hotel: hotel, base_price: 180)
      rate_plan = create(:rate_plan, room_type: room_type, name: "Best Available Rate")

      post bulk_save_ari_hotel_inventory_dashboards_path(hotel), params: {
        selection_update: {
          mode: "combined",
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          start_date: Date.current.to_s,
          end_date: Date.current.to_s,
          apply_inventory: "0",
          apply_rates: "1",
          apply_restrictions: "0",
          price: "333.00",
          currency: "MYR"
        }
      }

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, start_date: Date.current.to_s, room_type_id: room_type.id.to_s, rate_plan_id: rate_plan.id.to_s))
      expect(rate_plan.room_rates.find_by(date: Date.current, currency: "MYR").price.to_f).to eq(333.0)
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

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, tab: "advanced", subtab: "pricing", anchor: "top"))
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

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, tab: "advanced", subtab: "pricing", anchor: "top"))
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

    it "saves walk-in pricing rules successfully" do
      room_type = create(:room_type, hotel: hotel)

      post apply_pricing_rules_hotel_inventory_dashboards_path(hotel), params: {
        pricing_rule: {
          room_type_ids: [ room_type.id ],
          gp_price: "150",
          gp_start_date: "2026-05-20",
          gp_end_date: "2026-06-02",
          wi_price: "200",
          wi_start_date: "2026-05-20",
          wi_end_date: "2026-06-02"
        }
      }

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, start_date: "2026-05-20", tab: "advanced", subtab: "pricing", anchor: "top"))
      expect(hotel.pricing_rules.find_by(rule_type: "walk_in").price.to_f).to eq(200.0)
    end
  end

  describe "POST /apply_availability_override" do
    it "saves the selected room numbers as the inventory quantity" do
      room_type = create(:room_type, hotel: hotel, quantity: 10, room_numbers: [ "101", "102", "103", "104", "105", "106", "107", "108", "109", "110" ])

      post apply_availability_override_hotel_inventory_dashboards_path(hotel), params: {
        availability_override: {
          room_type_ids: [ room_type.id ],
          start_date: Date.current.to_s,
          end_date: Date.current.to_s,
          status: "open",
          room_numbers: [ "101", "102", "103", "104", "105", "106", "107", "108" ]
        }
      }

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, start_date: Date.current.to_s, tab: "advanced", subtab: "overrides", anchor: "top"))

      inventory = room_type.room_inventories.find_by(date: Date.current)
      expect(inventory.quantity).to eq(8)
      expect(inventory.available_room_numbers).to match_array([ "101", "102", "103", "104", "105", "106", "107", "108" ])
    end
  end

  describe "POST /update_channel_derived_pricing" do
    it "creates or updates a ChannelDerivedSetting record" do
      post update_channel_derived_pricing_hotel_inventory_dashboards_path(hotel), params: {
        channel_id: "test_channel_id",
        pricing_mode: "multiplier",
        pricing_value: "12.50"
      }

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, tab: "channels", subtab: "derived_settings"))
      setting = hotel.channel_derived_settings.find_by(channel_id: "test_channel_id")
      expect(setting).to be_present
      expect(setting.pricing_mode).to eq("multiplier")
      expect(setting.pricing_value.to_f).to eq(12.5)
    end
  end

  describe "POST /create_channel_availability_rule" do
    before do
      allow(ChannelManagers::SyncAvailabilityRuleJob).to receive(:perform_later)
    end

    it "creates a ChannelAvailabilityRule record" do
      post create_channel_availability_rule_hotel_inventory_dashboards_path(hotel), params: {
        title: "Test Rule",
        start_date: "2026-07-04",
        end_date: "2026-07-10",
        rule_type: "max_availability",
        value: "4",
        day_mo: "1",
        day_fr: "1",
        affected_channels: [ "ch_1" ],
        affected_room_types: [ 123 ]
      }

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, tab: "channels", subtab: "availability_rules"))
      rule = hotel.channel_availability_rules.find_by(title: "Test Rule")
      expect(rule).to be_present
      expect(rule.rule_type).to eq("max_availability")
      expect(rule.value).to eq(4)
      expect(rule.days).to eq("mo,fr")
      expect(rule.affected_channels).to eq([ "ch_1" ])
      expect(rule.affected_room_types).to eq([ 123 ])
    end
  end

  describe "DELETE /destroy_channel_availability_rule" do
    before do
      allow(ChannelManagers::SyncAvailabilityRuleJob).to receive(:perform_later)
    end

    it "destroys the specified availability rule" do
      rule = create(:channel_availability_rule, hotel: hotel, start_date: Date.current, rule_type: "close_out")

      delete destroy_channel_availability_rule_hotel_inventory_dashboards_path(hotel, id: rule.id)

      expect(response).to redirect_to(hotel_inventory_index_path(hotel, tab: "channels", subtab: "availability_rules"))
      expect(ChannelAvailabilityRule.find_by(id: rule.id)).to be_nil
    end
  end
end
