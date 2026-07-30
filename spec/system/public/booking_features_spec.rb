require "rails_helper"

RSpec.describe "Booking Features (Per Pax)", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved", time_zone: "UTC", allow_pax_pricing: true) }

  before do
    # Driven by cuprite
    driven_by(:cuprite, options: { window_size: [ 1400, 1000 ] })

    # Setup room type with high base price to avoid it being picked over rate plans
    @room_type = create(:room_type, hotel: hotel, max_adults: 4, max_children: 2, base_price: 1000.0)
    create(:room_inventory, room_type: @room_type, date: Date.current, quantity: 10, status: "open")
    create(:room_inventory, room_type: @room_type, date: Date.tomorrow, quantity: 10, status: "open")

    # Setup standard rate plan with corporate price
    @standard_plan = create(:rate_plan, hotel: hotel, name: "Standard Rate", sell_mode: "per_room")
    create(:room_type_rate_plan, room_type: @room_type, rate_plan: @standard_plan)
    @standard_rate = create(:room_rate, room_type: @room_type, rate_plan: @standard_plan, date: Date.current, price: 150.0, corporate_price: 120.0)

    # Setup per-pax rate plan
    @pax_plan = create(:rate_plan, hotel: hotel, name: "Per Pax Rate", sell_mode: "per_person")
    create(:room_type_rate_plan, room_type: @room_type, rate_plan: @pax_plan)
    @pax_rate = create(:room_rate, room_type: @room_type, rate_plan: @pax_plan, date: Date.current, price: 80.0)

    # Ensure hotel is publicly bookable
    hotel.update!(status: "approved")
  end

  it "calculates per-pax pricing correctly", js: true do
    # When pax_pricing_only is false:
    # We should only show per-room rate (150), never per-person rate (80),
    # regardless of whether adults = 1 or adults = 2.

    # Test 1 adult -> should pick Standard (150)
    visit hotel_path(hotel, check_in: Date.current, check_out: Date.tomorrow, adults: 1)
    within ".group", text: @room_type.name do
      expect(page).to have_content(/150/)
      expect(page).not_to have_content("PER-PAX BOOKING RULES")
    end

    # Test 2 adults -> should pick Standard (150)
    visit hotel_path(hotel, check_in: Date.current, check_out: Date.tomorrow, adults: 2)
    within ".group", text: @room_type.name do
      expect(page).to have_content(/150/)
      expect(page).not_to have_content("PER-PAX BOOKING RULES")
    end
  end

  it "forces per-pax pricing only when pax_pricing_only is enabled on the hotel", js: true do
    hotel.update!(allow_pax_pricing: true, pax_pricing_only: true)

    # 1 adult -> card shows price per person (80).
    # When added, sticky bar total price should be 80.
    visit hotel_path(hotel, check_in: Date.current, check_out: Date.tomorrow, adults: 1)
    within ".group", text: @room_type.name do
      expect(page).to have_content(/80/)
      click_button "Add to Stay"
    end
    within "[data-room-selector-target='stickyBar']" do
      expect(page).to have_content(/80\.00/)
    end

    # 2 adults -> card shows price per person (80).
    # When added, sticky bar total price should be 160.
    visit hotel_path(hotel, check_in: Date.current, check_out: Date.tomorrow, adults: 2)
    within ".group", text: @room_type.name do
      expect(page).to have_content(/80/)
      click_button "Add to Stay"
    end
    within "[data-room-selector-target='stickyBar']" do
      expect(page).to have_content(/160\.00/)
    end
  end
end
