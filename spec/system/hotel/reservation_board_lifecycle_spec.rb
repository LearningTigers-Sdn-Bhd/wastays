require "rails_helper"

RSpec.describe "Reservation Board Booking Lifecycle", type: :system do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "staff@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved", time_zone: "UTC") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }

  let(:permission_slugs) do
    [
      "view_reservation_board",
      "view_bookings",
      "manage_bookings",
      "post_folio_charges",
      "post_folio_payments",
      "execute_folio_refunds",
      "post_folio_adjustments",
      "post_folio_corrections",
      "post_folio_write_offs",
      "manage_night_audit",
      "view_reports"
    ]
  end

  before do
    driven_by(:cuprite, options: { window_size: [ 1400, 1000 ], process_timeout: 10 })

    permission_slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.humanize }
      role.permissions << permission unless role.permissions.include?(permission)
    end

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Setup room
    @room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    create(:room_status, hotel: hotel, room_type: @room_type, room_number: "101", status: "ready")

    # Freeze time to May 22, 2026, 10 AM
    @initial_time = Time.zone.local(2026, 5, 22, 10, 0, 0)
    travel_to @initial_time

    # Set business date to May 22
    @business_date = Date.new(2026, 5, 22)
    HotelBusinessDate.for_hotel_date!(hotel: hotel, date: @business_date)

    @booking = create(:booking,
      hotel: hotel,
      status: "confirmed",
      check_in: @business_date,
      check_out: @business_date + 1.day,
      guest_name: "John Doe"
    )
    create(:booking_room, booking: @booking, room_type: @room_type, room_number: "101")

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "completes a full booking lifecycle via the reservation board", js: true do
    # 1. Check-in
    visit hotel_reservation_board_index_path(hotel, start_date: @business_date)

    # The block exists but might not show the name directly (only in tooltip or sheet)
    expect(page).to have_selector("[data-booking-actions-id-value='#{@booking.id}']")

    # Click the booking block to open the sheet
    find("[data-booking-actions-id-value='#{@booking.id}']").click

    within "#offcanvas_drawer" do
      expect(page).to have_content(/John Doe/i)
      expect(page).to have_content(/Confirmed/i)
      click_button "Check In"
    end

    # Now we are in the native dialog modal
    within "dialog#check-in-modal-#{@booking.id}" do
      expect(page).to have_content(/Confirm Check-In/i)
      click_button "Confirm Check In"
    end

    # Assert status update on board
    expect(page).to have_selector("[data-booking-actions-id-value='#{@booking.id}'][data-booking-actions-status-value='checked_in']", wait: 5)
    expect(@booking.reload.status).to eq("checked_in")

    # 2. Night Audit (Simulate Day Roll)
    # Travel to the next day 10 AM to be past the business window
    travel_to @initial_time + 1.day

    perform_enqueued_jobs do
      result = HotelOps::RunNightAudit.new(
        hotel: hotel,
        business_date: @business_date,
        performed_by_user: user,
        trigger_mode: "manual",
        allow_unclosable_date: true
      ).call
      expect(result.success?).to be_truthy
    end

    # Reload board for the next day, but keep the start date to see the booking
    visit hotel_reservation_board_index_path(hotel, start_date: @business_date)

    # 3. Checkout
    # Record payment so checkout is not blocked
    Folios::PostStaffTransaction.call(
      folio: @booking.booking_folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: @booking.total_amount,
      description: "Full stay payment"
    )

    find("[data-booking-actions-id-value='#{@booking.id}']").click

    within "#offcanvas_drawer" do
      expect(page).to have_content(/Checked In/i)
      click_link "Check Out"
    end

    within "#offcanvas_drawer" do
      expect(page).to have_content(/Step 1 of 2/i)
      expect(page).to have_content(/Transaction Ledger/i)
      click_button "Complete Checkout"
    end

    # After checkout, the board should reload via Turbo Stream.
    # Completed bookings are hidden by default on the reservation board,
    # so we expect the booking block to disappear.
    expect(page).to have_no_selector("[data-booking-actions-id-value='#{@booking.id}']", wait: 5)
    expect(@booking.reload.status).to eq("completed")
  end
end
