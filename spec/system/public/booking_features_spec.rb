require "rails_helper"

RSpec.describe "Booking Features (Per Pax)", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved", time_zone: "UTC") }

  before do
    # Driven by cuprite
    driven_by(:cuprite, options: { window_size: [ 1400, 1000 ] })

    # Setup room type with high base price to avoid it being picked over rate plans
    @room_type = create(:room_type, hotel: hotel, max_adults: 4, max_children: 2, base_price: 1000.0)
    create(:room_inventory, room_type: @room_type, date: Date.current, quantity: 10, status: "open")
    create(:room_inventory, room_type: @room_type, date: Date.tomorrow, quantity: 10, status: "open")

    @standard_plan = @room_type.standard_rate_plan
    @standard_rate = create(:room_rate, room_type: @room_type, rate_plan: @standard_plan, date: Date.current, price: 150.0)

    # Ensure hotel is publicly bookable
    hotel.update!(status: "approved")
  end

  # A rate plan's mode follows its property, so the per-pax plan only exists
  # once the hotel itself sells per guest.
  def add_pax_plan!
    hotel.update!(sell_mode: "per_person")
    @pax_plan = create(:rate_plan, hotel: hotel, name: "Per Pax Rate")
    create(:room_type_rate_plan, room_type: @room_type, rate_plan: @pax_plan)
    @pax_rate = create(:room_rate, room_type: @room_type, rate_plan: @pax_plan, date: Date.current, price: 80.0)
  end

  it "calculates per-pax pricing correctly", js: true do
    # When the hotel sells per room the nightly rate is the room's (150),
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

  it "forces per-pax pricing only when the hotel sells per guest on the hotel", js: true do
    add_pax_plan!

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
