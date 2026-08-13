require 'rails_helper'

RSpec.describe "HotelPortal::InventoryDashboards", type: :request do
  let(:hotel) do
    create(
      :hotel,
      default_currency: "MYR",
      sell_mode: RSpec.current_example.metadata[:per_person] ? "per_person" : "per_room"
    )
  end
  let(:user) { create(:user) }
  let!(:room_type) { create(:room_type, hotel: hotel, max_adults: 2) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    role = create(:role, account: hotel.account)
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/inventory?tab=channels", :per_person do
    let(:channel_adapter) { instance_double(ChannelManagers::ChannexAdapter, connected_channels: []) }

    before do
      hotel.update!(preferred_channel_manager: "channex")
      room_type.update!(max_adults: 2)
      allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).with(hotel).and_return(channel_adapter)
    end

    it "identifies unsupported plans using their capability reason" do
      create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: "Incomplete OTA Rate")

      get hotel_inventory_index_path(hotel), params: { tab: "channels" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Some rates are not sent to OTAs")
      expect(response.body).to include("Incomplete OTA Rate: Complete the adult occupancy prices")
    end

    it "leaves internal plan kinds out of the unsupported warning" do
      create(:rate_plan, :walk_in_tier, hotel: hotel, room_type: room_type, name: "Walk In Rate")

      get hotel_inventory_index_path(hotel), params: { tab: "channels" }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Walk in plans are not distributed to channels")
    end

    it "identifies age-banded plans whose OTA child pricing is flattened" do
      plan = create(
        :rate_plan,
        :custom,
        hotel: hotel,
        room_type: room_type,
        name: "Family Rate",
        channex_children_fee: 20,
        channex_infant_fee: 0
      )
      assignment = plan.room_type_rate_plans.find_by!(room_type: room_type)
      assignment.occupancy_prices.create!(adults: 1, price: 100)
      assignment.occupancy_prices.create!(adults: 2, price: 180)
      create(:rate_plan_age_band, rate_plan: plan, min_age: 0, max_age: 17)

      get hotel_inventory_index_path(hotel), params: { tab: "channels" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Child prices are flattened for OTAs")
      expect(response.body).to include("Family Rate")
      expect(response.body).to include("Direct bookings continue to use age-specific prices")
    end
  end

  describe "GET /edit_selection" do
    let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Best Available") }

    it "shows only room-price occupancy fields when the property charges per room" do
      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: rate_plan.id, date: Date.current.to_s
      }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_field("selection_update[base_occupancy]")
      expect(page).to have_field("selection_update[extra_pax_charge]")
      expect(page).not_to have_field("selection_update[single_supplement]")
      expect(page).to have_content("Guests included")
      expect(page).to have_content("Extra guest charge")
      expect(page).to have_content("Room price (MYR)")
    end

    it "shows only per-guest occupancy fields when the property charges per guest", :per_person do
      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: rate_plan.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_field("selection_update[occupancy_prices][1]")
      expect(page).to have_field("selection_update[occupancy_prices][2]")
      expect(page).not_to have_field("selection_update[base_occupancy]")
      expect(page).not_to have_field("selection_update[extra_pax_charge]")
      expect(page).to have_content("Child prices and age groups come from the rate plan")
    end

    # The old dialog sized this grid to the largest room in the property and let
    # the save path silently drop anything above the category's own maximum.
    it "sizes the occupancy grid to the clicked category, not the property maximum", :per_person do
      create(:room_type, hotel: hotel, name: "Family Suite", max_adults: 4)

      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: rate_plan.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_field("selection_update[occupancy_prices][2]")
      expect(page).not_to have_field("selection_update[occupancy_prices][3]")
    end

    it "prefills the cell's saved values and preselects its room category and rate plan" do
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current,
             price: 250, currency: "MYR", min_stay: 2, max_stay: 5)

      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: rate_plan.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_field("selection_update[price]", with: "250.0")
      expect(page).to have_field("selection_update[min_stay]", with: "2")
      expect(page).to have_field("selection_update[max_stay]", with: "5")
      expect(page).to have_css("select[name='selection_update[room_type_context_id]'] option[selected][value='#{room_type.id}']", visible: :all)
      expect(page).to have_css("input[type='hidden'][name='selection_update[room_type_ids][]'][value='#{room_type.id}']", visible: :all)
      expect(page).not_to have_css("select[name='selection_update[room_type_ids][]']", visible: :all)
      expect(page).to have_css("select[name='selection_update[rate_plan_ids][]'] option[selected][value='#{rate_plan.id}']", visible: :all)
    end

    it "defaults to the selected category's first active plan when changing context" do
      other_room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      first_plan = other_room_type.rate_plans.active.order(:id).first

      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: other_room_type.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_css("select[name='selection_update[room_type_context_id]'] option[selected][value='#{other_room_type.id}']", visible: :all)
      expect(page).to have_css("select[name='selection_update[rate_plan_ids][]'] option[selected][value='#{first_plan.id}']", visible: :all)
      expect(page).to have_button("Stage update")
    end

    it "lists only active plans attached to the fixed category" do
      other_room_type = create(:room_type, hotel: hotel, name: "Ocean Villa King")
      shared_plan = create(:rate_plan, hotel: hotel, room_type: room_type, name: "Breakfast Rate", kind: "custom")
      create(:room_type_rate_plan, rate_plan: shared_plan, room_type: other_room_type)
      attached_plan = create(:rate_plan, room_type: room_type, name: "Member Rate")
      unrelated_plan = create(:rate_plan, room_type: other_room_type, name: "Villa Exclusive")
      archived_plan = create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: "Old Package")
      archived_plan.archive!

      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: shared_plan.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      options = page.all("select[name='selection_update[rate_plan_ids][]'] option[value='#{shared_plan.id}']", visible: :all)
      expect(options.size).to eq(1)
      expect(options.first.text).to eq("Breakfast Rate")
      expect(page).to have_css("option[value='#{attached_plan.id}']", text: "Member Rate", visible: :all)
      expect(page).not_to have_css("option[value='#{unrelated_plan.id}']", visible: :all)
      expect(page).not_to have_css("option[value='#{archived_plan.id}']", visible: :all)
    end

    it "renders availability fields without rate plans in availability mode" do
      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "availability", room_type_id: room_type.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_field("selection_update[quantity]")
      expect(page).to have_css("select[name='selection_update[room_type_context_id]'] option[selected][value='#{room_type.id}']", visible: :all)
      expect(page).to have_css("input[type='hidden'][name='selection_update[room_type_ids][]'][value='#{room_type.id}']", visible: :all)
      expect(page).not_to have_css("select[name='selection_update[room_type_ids][]']", visible: :all)
      expect(page).not_to have_field("selection_update[price]")
      expect(page).not_to have_css("select[name='selection_update[rate_plan_ids][]']", visible: :all)
    end

    it "renders a non-actionable state for an unknown calendar cell" do
      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: "999999", date: Date.current.to_s
      }

      expect(response).to have_http_status(:success)
      page = Capybara.string(response.body)
      expect(page).to have_content("This calendar item is no longer available")
      expect(page).to have_content("Refresh the calendar")
      expect(page).not_to have_button("Stage update")
      expect(page).not_to have_css("form#inventory-selection-form")
    end

    it "renders a non-actionable state for a rate plan from another category" do
      other_room_type = create(:room_type, hotel: hotel)
      other_plan = create(:rate_plan, room_type: other_room_type)

      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "rates", room_type_id: room_type.id, rate_plan_id: other_plan.id, date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_content("This calendar item is no longer available")
      expect(page).not_to have_button("Stage update")
    end

    it "renders a non-actionable state for an unknown room category" do
      get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
        mode: "availability", room_type_id: "999999", date: Date.current.to_s
      }

      page = Capybara.string(response.body)
      expect(page).to have_content("This calendar item is no longer available")
      expect(page).not_to have_button("Stage update")
      expect(page).not_to have_css("form#inventory-selection-form")
    end

    # An OTA row is reached through a channel rate plan that belongs to one
    # category, so there is nothing to switch to and no originating rate plan to
    # name in the hint. Both used to be assumed present.
    context "on a channel availability cell" do
      let(:channel_data) do
        {
          "id" => "chan-123",
          "attributes" => {
            "title" => "BookingCom",
            "channel" => "BookingCom",
            "settings" => { "mappingSettings" => { "rooms" => { "ota_room_id" => "ext-rt-mapped" } } }
          }
        }
      end

      before do
        hotel.update!(preferred_channel_manager: "channex")
        create(:channel_mapping, mappable: room_type, provider: "channex", external_id: "ext-rt-mapped")
        allow_any_instance_of(HotelPortal::InventoryCalendarPresenter)
          .to receive(:connected_channels).and_return([ channel_data ])
      end

      it "renders without a room category switcher or an originating rate plan" do
        get edit_selection_hotel_inventory_dashboards_path(hotel), params: {
          mode: "channel_availability", room_type_id: room_type.id,
          channel_id: "chan-123", date: Date.current.to_s
        }

        expect(response).to have_http_status(:success)
        page = Capybara.string(response.body)
        expect(page).not_to have_content("This calendar item is no longer available")
        expect(page).not_to have_css("select[name='selection_update[room_type_context_id]']", visible: :all)
        expect(page).to have_content("Every selected plan receives the same update.")
        expect(page).not_to have_content("Values below come from")
      end
    end
  end

  describe "GET /index" do
    it "links each cell to the editor instead of carrying the form inline" do
      rate_plan = create(:rate_plan, room_type: room_type, name: "Best Available")

      get hotel_inventory_index_path(hotel), params: { start_date: Date.current.to_s }

      page = Capybara.string(response.body)
      expect(page).not_to have_field("selection_update[price]")
      expect(page).to have_css(
        "a[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}'][data-turbo-frame='inventory_selection_sheet']"
      )
      expect(page).to have_css("turbo-frame#inventory_selection_sheet", visible: :all)
    end

    it "renders validated tabs and nested breadcrumb labels" do
      get hotel_inventory_index_path(hotel), params: { tab: "advanced", subtab: "overrides" }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_css('[data-panels-ui--tabs-active-value="advanced"]')
      expect(page).to have_css("[data-testid='inventory-calendar-panel']", visible: :all)
      expect(page).to have_css("[data-testid='inventory-advanced-panel']")
      expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Advanced Pricing")
      expect(page).to have_css("[data-subtabs-breadcrumb-label]", text: "Availability Overrides")
    end

    it "falls back to the default tab and subtab for unknown parameters" do
      get hotel_inventory_index_path(hotel), params: { tab: "unknown", subtab: "unknown" }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_css('[data-panels-ui--tabs-active-value="calendar"]')
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

      get "/hotel/#{hotel.to_param}/inventory", params: { start_date: Date.current.to_s }

      expect(response).to have_http_status(:success)

      page = Capybara.string(response.body)
      expect(page).to have_content("Rates & Availability")
      expect(page).to have_css("[data-testid='inventory-calendar-grid']")
      expect(page).to have_button("Confirm Update", disabled: true, visible: :all)
      expect(page).to have_content("Pricing Rules")
      expect(page).to have_content("Availability Overrides")
    end

    it "renders rate rows with room-type filtering in toolbar" do
      deluxe = create(:room_type, hotel: hotel, name: "Deluxe Room", quantity: 4)
      twin = create(:room_type, hotel: hotel, name: "Twin Room", quantity: 2)
      deluxe_plan = create(:rate_plan, room_type: deluxe, name: "Best Available")
      create(:rate_plan, room_type: twin, name: "Non Refundable")
      create(:room_rate, room_type: deluxe, rate_plan: deluxe_plan, date: Date.current, price: 320, currency: "MYR")

      get "/hotel/#{hotel.to_param}/inventory", params: {
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

      get "/hotel/#{hotel.to_param}/inventory", params: { display_currency: "MYR", start_date: Date.current.to_s }

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

  describe "GET /occupancy_details" do
    it "renders guest bookings grouped by room type with target=_blank link to their booking" do
      room_type = create(:room_type, hotel: hotel, name: "Luxury Suite")
      booking = create(:booking, hotel: hotel, guest_name: "Alice Cooper", check_in: Date.current, check_out: Date.current + 2.days, status: "confirmed")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "502")

      get occupancy_details_hotel_inventory_dashboards_path(hotel), params: { date: Date.current.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Alice Cooper")
      expect(response.body).to include("Luxury Suite")
      expect(response.body).to include("502")
      expect(response.body).to include("href=\"/hotel/#{hotel.to_param}/bookings/#{booking.id}\"")
      expect(response.body).to include("target=\"_blank\"")
      expect(response.body).to include(Date.current.strftime("%b %-d"))
      expect(response.body).to include("2 nights")
    end
  end
end
