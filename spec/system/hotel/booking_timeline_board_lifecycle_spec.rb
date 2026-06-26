require "rails_helper"

RSpec.describe "Booking Timeline Board Booking Lifecycle", type: :system do
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

  def drag_booking_to(booking:, room_number:, date:)
    page.execute_script(<<~JS)
      const source = document.querySelector("[data-booking-actions-id-value='#{booking.id}']")
      const handle = source.querySelector("[data-action*='onDragHandleMouseDown']")
      const target = document.querySelector("[data-room-number='#{room_number}'][data-date='#{date}']")
      const transfer = new DataTransfer()
      handle.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }))
      source.dispatchEvent(new DragEvent("dragstart", { bubbles: true, dataTransfer: transfer }))
      target.dispatchEvent(new DragEvent("dragover", { bubbles: true, dataTransfer: transfer }))
      target.dispatchEvent(new DragEvent("drop", { bubbles: true, dataTransfer: transfer }))
      source.dispatchEvent(new DragEvent("dragend", { bubbles: true, dataTransfer: transfer }))
    JS
  end

  def wait_for_booking_timeline_controller
    expect(page).to have_selector("[data-controller~='booking-timeline']")
    page.document.synchronize do
      connected = page.evaluate_script(<<~JS)
        (() => {
          const element = document.querySelector("[data-controller~='booking-timeline']")
          return Boolean(element && window.Stimulus?.getControllerForElementAndIdentifier(element, "booking-timeline"))
        })()
      JS
      raise Capybara::ElementNotFound, "booking-timeline Stimulus controller is not connected" unless connected
    end
  end

  def resize_booking_to(booking:, room_number:, date:)
    source_selector = "[data-booking-actions-id-value='#{booking.id}']"
    handle_selector = "#{source_selector} [data-booking-timeline-target='resizeHandle']"
    target_selector = "[data-room-number='#{room_number}'][data-date='#{date}']"

    expect(page).to have_selector(source_selector)
    expect(page).to have_selector(handle_selector)
    expect(page).to have_selector(target_selector)
    wait_for_booking_timeline_controller

    page.execute_script(<<~JS)
      const source = document.querySelector("#{source_selector}")
      const handle = document.querySelector("#{handle_selector}")
      const target = document.querySelector("#{target_selector}")
      target.scrollIntoView({ block: "center", inline: "center" })

      const startRect = handle.getBoundingClientRect()
      const targetRect = target.getBoundingClientRect()
      const start = { x: startRect.left + (startRect.width / 2), y: startRect.top + (startRect.height / 2) }
      const finish = { x: targetRect.left + (targetRect.width / 2), y: targetRect.top + (targetRect.height / 2) }

      handle.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, clientX: start.x, clientY: start.y }))
      document.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, clientX: finish.x, clientY: finish.y }))
      document.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, clientX: finish.x, clientY: finish.y }))
    JS
  end

  def expect_offcanvas_to_finish_closing
    expect(page).to have_selector("#offcanvas_drawer_container.hidden", visible: :all)
    expect(page).to have_selector("#offcanvas_drawer:not([src])", visible: :all)
    expect(page).to have_no_content("Move Stay")
  end

  def expect_offcanvas_to_finish_opening
    expect(page).to have_selector(
      "#offcanvas_drawer_container.block [data-offcanvas-target='panel'].translate-x-0",
      visible: :all
    )
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time

    loop do
      transform = page.evaluate_script(<<~JS)
        window.getComputedStyle(
          document.querySelector("#offcanvas_drawer_container [data-offcanvas-target='panel']")
        ).transform
      JS
      break if transform == "none" || transform == "matrix(1, 0, 0, 1, 0, 0)"
      raise "Offcanvas panel did not finish opening" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
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
    @room_type = create(:room_type, hotel: hotel, room_numbers: [ "101", "102" ])
    create(:room_status, hotel: hotel, room_type: @room_type, room_number: "101", status: "ready")
    create(:room_status, hotel: hotel, room_type: @room_type, room_number: "102", status: "ready")

    # Freeze time to May 22, 2026, 10 AM
    @initial_time = Time.zone.local(2026, 5, 22, 10, 0, 0)
    travel_to @initial_time

    # Set business date to May 22
    @business_date = Date.new(2026, 5, 22)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: @business_date)

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

  it "completes a full booking lifecycle via the Booking Timeline Board", js: true do
    # 1. Check-in
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    # The block exists but might not show the name directly (only in tooltip or sheet)
    expect(page).to have_selector("[data-booking-actions-id-value='#{@booking.id}']")

    # Click the booking block to open the sheet
    find("[data-booking-actions-id-value='#{@booking.id}']").click

    within "#offcanvas_drawer" do
      expect(page).to have_field("Guest name", with: "John Doe")
    end
    page.execute_script("document.getElementById('offcanvas_drawer').src = '#{hotel_booking_transaction_check_in_reservation_path(hotel, @booking, source: "booking_timeline_board")}'")

    within "#offcanvas_drawer" do
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
      result = NightAudits::Run.new(
        hotel: hotel,
        business_date: @business_date,
        performed_by_user: user,
        trigger_mode: "manual",
        allow_unclosable_date: true
      ).call
      expect(result.success?).to be_truthy
    end

    # Reload board for the next day, but keep the start date to see the booking
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

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
      expect(page).to have_link("Check Out")
    end
    page.execute_script("document.getElementById('offcanvas_drawer').src = '#{hotel_booking_transaction_check_out_path(hotel, @booking, source: "booking_timeline_board")}'")

    within "#offcanvas_drawer" do
      expect(page).to have_content(/Step 1 of 2/i)
      expect(page).to have_content(/Folio List/i)
      click_button "Complete Checkout"
    end

    # After checkout, the board should reload via Turbo Stream.
    # Completed bookings are hidden by default on the Booking Timeline Board,
    # so we expect the booking block to disappear.
    expect(page).to have_no_selector("[data-booking-actions-id-value='#{@booking.id}']", wait: 5)
    expect(@booking.reload.status).to eq("completed")
  end

  it "opens a booking from the keyboard and closes the amend-stay drawer", js: true do
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    booking_block = find("[data-booking-actions-id-value='#{@booking.id}']")
    booking_block.send_keys(:enter)

    within "#offcanvas_drawer" do
      expect(page).to have_field("Guest name", with: "John Doe")
      page.execute_script("document.getElementById('offcanvas_drawer').src = '#{hotel_booking_transaction_amend_stay_path(hotel, @booking)}'")
      expect(page).to have_content(/Edit Stay & Room/i)
      find_button("Cancel").trigger("click")
    end

    expect(page).to have_selector("#offcanvas_drawer_container.hidden", visible: :all)
  end

  it "opens today slot actions and prefills the selected room", js: true do
    visit board_hotel_bookings_path(hotel, start_date: @business_date)
    board_url = page.current_url

    cell = find("[data-room-number='102'][data-date='#{@business_date}']")
    cell.find("button[aria-haspopup='menu']").click

    menu = find("body > [role='menu'][aria-label*='Booking actions for room 102']", visible: true)
    expect(menu["style"]).to include("position: fixed", "z-index: 9999")
    expect(menu).to have_content("Room 102")
    expect(menu).to have_content("Walk-in Check-in")
    expect(menu).to have_content("Add Booking")

    menu.click_link "Add Booking"

    expect(page.current_url).to eq(board_url)
    expect(page).to have_selector("#offcanvas_drawer_container.block", visible: :all)
    within "#offcanvas_drawer" do
      expect(page).to have_content(/New Booking/i)
      expect(page).to have_select("Room Number", selected: "102")
    end
    expect(page).to have_no_selector("body > [role='menu'][aria-label*='Booking actions for room 102']", visible: :all)
    expect(cell).to have_selector("[role='menu'][aria-label*='Booking actions for room 102'].hidden", visible: :all)
  end

  it "opens a walk-in from today slot actions without leaving the board", js: true do
    visit board_hotel_bookings_path(hotel, start_date: @business_date)
    board_url = page.current_url

    cell = find("[data-room-number='102'][data-date='#{@business_date}']")
    cell.find("button[aria-haspopup='menu']").click
    menu = find("body > [role='menu'][aria-label*='Booking actions for room 102']", visible: true)
    menu.click_link "Walk-in Check-in"

    expect(page.current_url).to eq(board_url)
    expect(page).to have_selector("#offcanvas_drawer_container.block", visible: :all)
    within "#offcanvas_drawer" do
      expect(page).to have_content(/Walk[ -]in check[ -]in/i)
      expect(page).to have_select("Room Number", selected: "102")
    end
    expect(page).to have_no_selector("body > [role='menu'][aria-label*='Booking actions for room 102']", visible: :all)
    expect(cell).to have_selector("[role='menu'][aria-label*='Booking actions for room 102'].hidden", visible: :all)
  end

  it "restores a portaled slot menu after Escape", js: true do
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    cell = find("[data-room-number='102'][data-date='#{@business_date}']")
    trigger = cell.find("button[aria-haspopup='menu']")
    trigger.click
    menu = find("body > [role='menu'][aria-label*='Booking actions for room 102']", visible: true)

    trigger.send_keys(:escape)

    expect(page).to have_no_selector("body > [role='menu'][aria-label*='Booking actions for room 102']", visible: :all)
    expect(cell).to have_selector("[role='menu'][aria-label*='Booking actions for room 102'].hidden", visible: :all)
    expect(trigger["aria-expanded"]).to eq("false")
  end

  it "does not open Edit Booking from a timeline handle", js: true do
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    page.execute_script(<<~JS)
      const source = document.querySelector("[data-booking-actions-id-value='#{@booking.id}']")
      source.querySelector("[data-booking-timeline-target='dragHandle']").click()
    JS
    expect(page).to have_selector("#offcanvas_drawer_container.hidden", visible: :all)
    expect(page).to have_no_content("Edit Booking")
  end

  it "cancels a proposed move without changing the booking", js: true do
    target_date = @business_date + 1.day
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    drag_booking_to(booking: @booking, room_number: "102", date: target_date)
    expect_offcanvas_to_finish_opening

    within "#offcanvas_drawer" do
      expect(page).to have_content(/Move Stay/i)
      find_button("Cancel", exact: true).trigger("click")
    end

    expect_offcanvas_to_finish_closing
    expect(@booking.reload.check_in.to_date).to eq(@business_date)
    expect(@booking.check_out.to_date).to eq(@business_date + 1.day)
    expect(@booking.booking_rooms.first.room_number).to eq("101")
  end

  it "moves a booking by dragging its handle and confirming the timeline sheet", js: true do
    target_date = @business_date + 1.day
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    drag_booking_to(booking: @booking, room_number: "102", date: target_date)
    expect_offcanvas_to_finish_opening

    within "#offcanvas_drawer" do
      expect(page).to have_content(/Move Stay/i)
      click_button "Confirm Move"
    end

    expect(page).to have_selector(
      "[data-booking-actions-id-value='#{@booking.id}'][data-booking-actions-check-in-value='#{target_date}']",
      wait: 5
    )
    expect(@booking.reload.check_in.to_date).to eq(target_date)
    expect(@booking.check_out.to_date).to eq(target_date + 1.day)
    expect(@booking.booking_rooms.first.room_number).to eq("102")
  end

  it "extends a booking by resizing it and confirming the timeline sheet", js: true do
    target_date = @business_date + 2.days
    proposed_check_out = target_date.next_day
    visit board_hotel_bookings_path(hotel, start_date: @business_date)

    resize_booking_to(booking: @booking, room_number: "101", date: target_date)

    expect(page).to have_selector("#offcanvas_drawer[src*='timeline_action=extend'][src*='check_out=#{proposed_check_out}']", visible: :all)
    expect_offcanvas_to_finish_opening
    within "#offcanvas_drawer" do
      expect(page).to have_content(/Extend Stay/i)
      click_button "Confirm Extension"
    end

    expect(page).to have_selector("[data-booking-actions-id-value='#{@booking.id}']", wait: 5)
    expect(@booking.reload.check_out.to_date).to eq(proposed_check_out)
  end
end
