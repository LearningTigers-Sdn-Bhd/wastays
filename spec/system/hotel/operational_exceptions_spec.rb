require "rails_helper"

RSpec.describe "Operational Exceptions", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, :superadmin, account: account, email: "operational-exceptions-#{SecureRandom.hex(4)}@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:role) { create(:role, account: account, slug: "manager", name: "Manager") }
  let(:room_type) { create(:room_type, hotel: hotel) }

  before do
    driven_by(:cuprite)

    # Give all required permissions
    %w[view_bookings manage_bookings post_folio_charges post_folio_payments execute_folio_refunds view_reports override_financial_date_lock].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.titleize }
      role.permissions << permission
    end

    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  describe "Late Checkout" do
    it "allows front desk to review and apply a late checkout charge" do
      # Set business date to today
      travel_to Time.zone.local(2026, 5, 21, 10, 0, 0)

      booking = create(:booking, hotel: hotel, status: "review_due_out", guest_name: "John Doe", check_in: 1.day.ago, check_out: Date.current, total_amount: 100.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 100.0, quantity: 1, nightly_rate_snapshot: { 1.day.ago.to_date.iso8601 => { "price" => 100.0 } })
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      visit hotel_booking_path(hotel, booking)

      expect(page).to have_content("Review Late Checkout")
      click_link "Review Late Checkout"

      expect(page).to have_content("Current Rate Charge")

      # Select custom charge
      find("label", text: "Additional Charge").click

      # Wait for custom section to appear
      expect(page).to have_selector("[data-late-checkout-target='customSection']", visible: true)

      # Fill in the custom value
      find("[data-late-checkout-target='customValue']").set("75.00")

      expect(page).to have_content("MYR 174.99")

      click_button "Process Late Checkout"

      expect(booking.reload.status).to eq("checked_in")
      expect(folio.reload.outstanding_balance).to eq(174.99)
    end
  end

  describe "Early Departure" do
    it "shows early departure review in checkout modal and applies charge" do
      travel_to Time.zone.local(2026, 5, 21, 10, 0, 0)
      business_date = hotel.business_date_for

      # Future checkout
      booking = create(:booking, hotel: hotel, status: "checked_in", guest_name: "Jane Smith", check_in: 1.day.ago, check_out: 3.days.from_now, total_amount: 400.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 400.0, quantity: 1, nightly_rate_snapshot: {
        1.day.ago.to_date.iso8601 => { "price" => 100.0 },
        Date.current.iso8601 => { "price" => 100.0 },
        1.day.from_now.to_date.iso8601 => { "price" => 100.0 },
        2.days.from_now.to_date.iso8601 => { "price" => 100.0 }
      })
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      # Let's post the nightly charge for yesterday
      audit = hotel.night_audits.create!(business_date: 1.day.ago.to_date, status: "running", trigger_mode: "manual")
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: 1.day.ago.to_date)
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit, user: user)
      audit.update!(status: "completed")
      close_and_open_next_business_date(hotel)

      # Pay the full 550: 100 (stay) + 300 (early checkout charges) + 150 (penalty)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 550.0, user: user, posting_date: business_date)

      visit hotel_booking_path(hotel, booking)

      # Open the shared fullscreen checkout sheet.
      click_link "Check Out"

      # Wait for the compact early-departure controls to appear.
      expect(page).to have_content(/Early departure/i, wait: 10)
      expect(page).to have_content("Upcoming charges to post")

      # Select Apply Charge
      find("input[name='apply_charge'][value='true']", visible: :all).trigger("click")

      expect(page).to have_selector("[data-early-departure-target='customFields']", visible: true)

      # Fill in details
      input = find("[name='early_departure[value]']", visible: :all)
      input.set("150.00")
      input.send_keys(:tab) # trigger blur/change to ensure stimulus updates balance

      # Wait a moment for any Stimulus JS calculations to update the form state (e.g. disabling/enabling the complete button)
      # We know the outstanding balance should become 0.00 after the 150.00 penalty is added.
      expect(page).to have_selector("*", text: "MYR 0.00", visible: :all, wait: 5)

      # Submit the form via Capybara's native click (no visible: all) after scrolling it into view
      page.execute_script("document.querySelector('input[value=\"Complete Checkout\"]').scrollIntoView({block: 'center'})")
      click_button "Complete Checkout"

      # After checkout, redirects to show page with flash notice
      expect(page).to have_content("Guest has been checked out.")

      expect(booking.reload.status).to eq("completed")
      expect(booking.check_out.to_date).to eq(business_date)
      expect(folio.reload.folio_transactions.charge.find_by(category: "early_departure_charge").amount).to eq(150.0)
    end
  end
end
