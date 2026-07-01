require "rails_helper"

RSpec.describe "Booking Features (Agent & Per Pax)", type: :system do
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

    # Setup agent
    @agent = create(:agent_account, hotel: hotel, name: "Test Agent", agent_code: "AGENT123")

    # Ensure hotel is publicly bookable
    hotel.update!(status: "approved")
  end

  it "applies agent code, shows corporate price, and records agent on booking", js: true do
    # Visit with dates to ensure search is active
    visit hotel_path(hotel, check_in: Date.current, check_out: Date.tomorrow)

    # Enter agent code
    fill_in "agent_code", with: "AGENT123"

    # Click search button
    find('button[type="submit"]').click

    expect(page).to have_content("Agent Code Applied: Test Agent")

    # Standard price is 150, corporate is 120.
    within ".group", text: @room_type.name do
      expect(page).to have_content(/120/)
      click_button "Add to Stay"
    end

    # Wait for Stimulus to update the sticky bar and form inputs
    expect(page).to have_content("MYR 120.00")

    click_button "Book Selected"

    # Now on the quote page. Wait for it to load.
    expect(page).to have_content("Complete Your Booking")

    # Get the quote token from the URL or session if needed, but we can just use the mock_payment path.
    # Actually, we can just navigate to the mock payment page for the quote.
    quote = BookingQuote.last
    visit mock_payment_path(quote_token: quote.token)

    # Fill in guest details for the mock payment
    fill_in "guest_details_name", with: "Agent Guest"
    fill_in "guest_details_email", with: "guest@example.com"
    fill_in "guest_details_phone", with: "123456789"
    fill_in "government_id", with: "ID12345"
    select "Male", from: "guest_details_gender"
    fill_in "guest_details_country", with: "Malaysia"
    select "MyKad / IC", from: "guest_details_document_type"

    click_button "Confirm Payment"

    expect(page).to have_content("Payment successful!")

    # Verify the booking
    booking = Booking.last
    expect(booking.agent_account_id).to eq(@agent.id)
    expect(booking.total_amount).to be_within(1.0).of(120.0)
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
      expect(page).to have_content("PER-PAX BOOKING RULES")
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
      expect(page).to have_content("PER-PAX BOOKING RULES")
      click_button "Add to Stay"
    end
    within "[data-room-selector-target='stickyBar']" do
      expect(page).to have_content(/160\.00/)
    end
  end
end
