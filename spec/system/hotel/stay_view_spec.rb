# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel Stay View", type: :system, js: true do
  around { |example| travel_to(Time.zone.local(2026, 7, 16, 10, 0, 0)) { example.run } }

  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "approved", accounting_business_date: Date.current) }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "front_desk", name: "Front Desk") }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101 102]) }
  let!(:booking) do
    create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 2.days).tap do |record|
      create(:booking_room, booking: record, room_type:, room_number: "101")
    end
  end

  before do
    %w[view_bookings manage_bookings manage_guest_arrival manage_room_status].each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_through_ui(user)
  end

  def dispatch_pointer_down(segment_id:, edge: nil, pointer_type: "mouse", pointer_id: 41)
    page.execute_script(<<~JS)
      (() => {
        const segment = document.getElementById(#{segment_id.to_json})
        const source = #{edge.to_json} ? segment.querySelector(`[data-resize-edge="${#{edge.to_json}}"]`) : segment.querySelector(".panel-timeline__segment-content")
        const rect = source.getBoundingClientRect()
        window.phaseFivePointer = {
          segmentId: #{segment_id.to_json}, pointerId: #{pointer_id}, pointerType: #{pointer_type.to_json},
          x: rect.left + rect.width / 2, y: rect.top + rect.height / 2
        }
        source.dispatchEvent(new PointerEvent("pointerdown", {
          bubbles: true, cancelable: true, pointerId: #{pointer_id}, pointerType: #{pointer_type.to_json},
          isPrimary: true, button: 0, clientX: window.phaseFivePointer.x, clientY: window.phaseFivePointer.y
        }))
      })()
    JS
  end

  def dispatch_pointer_finish(room_number:, day_delta:, pointer_id: 41)
    page.execute_script(<<~JS)
      (() => {
        const pointer = window.phaseFivePointer
        const row = document.querySelector(`[data-room-number="#{room_number}"][data-stay-view--interaction-target~="row"]`)
        const rowRect = row.querySelector(".panel-timeline__row-track").getBoundingClientRect()
        const dayWidth = row.querySelector(".panel-timeline__cell").getBoundingClientRect().width
        const x = pointer.x + (dayWidth * #{day_delta})
        const y = rowRect.top + rowRect.height / 2
        window.dispatchEvent(new PointerEvent("pointermove", {
          bubbles: true, cancelable: true, pointerId: #{pointer_id}, pointerType: pointer.pointerType,
          isPrimary: true, button: 0, clientX: x, clientY: y
        }))
        window.dispatchEvent(new PointerEvent("pointerup", {
          bubbles: true, cancelable: true, pointerId: #{pointer_id}, pointerType: pointer.pointerType,
          isPrimary: true, button: 0, clientX: x, clientY: y
        }))
      })()
    JS
  end

  def drag_booking(room_number:, day_delta:, edge: nil, pointer_type: "mouse", long_press: false)
    segment_id = "stay_view_booking_room_#{booking.booking_rooms.sole.id}"
    dispatch_pointer_down(segment_id:, edge:, pointer_type:)
    sleep 0.4 if long_press
    dispatch_pointer_finish(room_number:, day_delta:)
  end

  it "switches between URL-backed views and restores the prior view with browser history" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    expect(page).to have_css("#stay-view-timeline")
    click_link "Rooms"
    expect(page).to have_css("[data-testid='stay-view-room-cards']")
    expect(URI.parse(page.current_url).query).to include("view=rooms", "date=2026-07-16")

    page.go_back
    expect(URI.parse(page.current_url).query).to include("view=timeline", "days=7")
    expect(page).to have_css("#stay-view-timeline", wait: 10)

    page.go_forward
    expect(page).to have_css("[data-testid='stay-view-room-cards']", wait: 10)
    expect(URI.parse(page.current_url).query).to include("view=rooms", "date=2026-07-16")
  end

  it "shows booking details on hover and keyboard focus without replacing click navigation" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    segment = find("#stay_view_booking_room_#{booking.booking_rooms.sole.id}")
    segment.hover
    expect(page).to have_css("##{segment[:id]}-panel", text: "Ada Lovelace", visible: :visible)
    expect(page).to have_css("##{segment[:id]}-panel", text: "Single booking", visible: :visible)
    expect(URI.parse(segment.find("a")[:href]).path).to eq(hotel_booking_transaction_show_booking_path(hotel, booking))

    page.execute_script("document.querySelector('##{segment[:id]}-trigger').focus()")
    expect(page).to have_css("##{segment[:id]}-panel", text: "Confirmed", visible: :visible)
  end

  it "opens date-aware available-cell actions by keyboard and launches the existing booking sheet" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    trigger_id = "stay_view_room_#{room_type.id}_102-#{Date.current.iso8601}-cell-actions-trigger"
    page.execute_script("document.getElementById('#{trigger_id}').focus()")
    find("##{trigger_id}").send_keys(:down)

    menu_id = "stay_view_room_#{room_type.id}_102-#{Date.current.iso8601}-cell-actions-menu"
    expect(page).to have_css("##{menu_id}", text: "Walk-in check-in", visible: :visible)
    within("##{menu_id}") { click_link "Add booking" }

    within("#offcanvas_drawer") do
      expect(find("#booking_check_in").value).to start_with(Date.current.iso8601)
      expect(find("#booking_check_out").value).to start_with((Date.current + 1.day).iso8601)
    end
  end

  it "opens the status guide by click and room status details by hover, focus, and tap" do
    create(:room_status, hotel:, room_type:, room_number: "102", status: "dirty")
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    find("button[aria-label='Stay View status guide']").click
    expect(page).to have_css("#stay-view-status-guide-panel", text: "No-show review", visible: :visible)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Do not disturb", visible: :visible)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Cleaning priority", visible: :visible)
    expect(page).to have_no_css("#stay-view-status-guide-panel", text: "Timeline events", visible: :all)
    find("button[aria-label='Stay View status guide']").click

    status_trigger = find("#stay_view_room_#{room_type.id}_102-status-trigger")
    status_trigger.hover
    expect(page).to have_css("#stay_view_room_#{room_type.id}_102-status-panel", text: "Dirty", visible: :visible)

    page.execute_script("document.getElementById('stay_view_room_#{room_type.id}_102-status-trigger').focus()")
    expect(page).to have_css("#stay_view_room_#{room_type.id}_102-status-panel", text: "Dirty", visible: :visible)

    status_trigger.click
    expect(page).to have_css("#stay_view_room_#{room_type.id}_102-status-panel", text: "Dirty", visible: :visible)
  end

  it "shows authorized projected financial signals in Timeline and Room views" do
    permission = Permission.find_or_create_by!(slug: "view_financial_status") do |record|
      record.name = "View Financial Status"
    end
    RolePermission.find_or_create_by!(role:, permission:)
    folio = create(:booking_folio, booking:, hotel:)
    create(:booking_guest, booking:, guest: create(:guest, name: "Ada Lovelace"), is_primary: true)
    create(:folio_transaction, booking_folio: folio, amount: 240)

    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    segment = find("#stay_view_booking_room_#{booking.booking_rooms.sole.id}")
    expect(segment).to have_css(
      "[data-slot='stay-view-financial-attention']" \
      "[aria-label='Guest: Ada Lovelace · Balance due · MYR 240.00']"
    )
    page.execute_script("document.querySelector('##{segment[:id]}-trigger').focus()")
    expect(page).to have_css(
      "##{segment[:id]}-panel",
      text: "Guest: Ada Lovelace · Balance due · MYR 240.00",
      visible: :visible
    )

    click_link "Rooms"
    expect(page).to have_css(
      "[data-slot='stay-view-financial-signal'][data-variant='warning']",
      text: "Guest: Ada Lovelace · Balance due · MYR 240.00"
    )
  end

  it "shows operational indicators and completes housekeeping workflows from Room View" do
    plan = create(:plan)
    hotel.update!(plan:)
    feature = create(:feature, slug: "task_assignment_minibar_log")
    create(:plan_feature, plan:, feature:, enabled: true)
    %w[manage_housekeeping_tasks manage_requests].each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
    housekeeper_role = create(:role, account:, slug: "housekeeper", name: "Housekeeper")
    housekeeper = create(:user, account:, name: "Sam Lee", role: "hotel_staff")
    create(:user_hotel_access, user: housekeeper, hotel:, role: housekeeper_role)
    create(:room_status, hotel:, room_type:, room_number: "101", status: "cleaning", priority: true, dnd: true, dnd_date: Date.current)
    housekeeping_request = create(
      :housekeeping_request,
      booking: nil,
      hotel:,
      room_type:,
      room_number: "101",
      status: "new",
      request_details: "Fresh towels"
    )

    visit hotel_stay_view_path(hotel, view: :rooms, date: Date.current)

    within("#stay_view_room_#{room_type.id}_101") do
      expect(page).to have_css("[role='img'][aria-label='Do not disturb']")
      expect(page).to have_css("[role='img'][aria-label='Cleaning priority']")
      find("button[aria-label='1 active housekeeping request']").click
      expect(page).to have_css("#stay_view_room_#{room_type.id}_101-housekeeping-panel", text: "Fresh towels", visible: :visible)
    end

    find("button[aria-label='Actions for room 101']").click
    click_link "Assign room tasks"
    within("#offcanvas_drawer") do
      expect(page).to have_content("updates all active housekeeping requests")
      find("#assignment_assigned_to-trigger").click
      find("[role='option']", text: "Sam Lee").click
      click_button "Save assignment"
    end
    expect(housekeeping_request.reload.metadata).to include("assigned_to_name" => "Sam Lee")

    find("button[aria-label='Actions for room 101']").click
    click_link "Update task status — Fresh towels"
    within("#offcanvas_drawer") do
      find("#housekeeping_request_status-trigger").click
      find("[role='option']", text: "Completed").click
      click_button "Update status"
    end

    expect(page).to have_no_css("button[aria-label='1 active housekeeping request']")
    expect(housekeeping_request.reload.status).to eq("completed")
    expect(hotel.room_statuses.find_by(room_type:, room_number: "101").status).to eq("ready")
  end

  it "nests Timeline booking actions by guest and opens the selected action sheet" do
    duplicate = create(
      :booking,
      hotel:,
      guest_name: booking.guest_name,
      check_in: Date.current + 3.days,
      check_out: Date.current + 4.days
    )
    create(:booking_room, booking: duplicate, room_type:, room_number: "101")

    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    find("button[aria-label='Actions for room 101']").click
    click_button "Booking"
    expect(page).to have_button("Ada Lovelace · 2026-07-16–2026-07-18")
    expect(page).to have_button("Ada Lovelace · 2026-07-19–2026-07-20")
    click_button "Ada Lovelace · 2026-07-16–2026-07-18"
    click_link "Move or reassign"

    within("#offcanvas_drawer") do
      expect(page).to have_content("Move or reassign stay")
      expect(page).to have_content("Ada Lovelace")
    end
  end

  it "moves a stay without dragging and refreshes the Room View board" do
    visit hotel_stay_view_path(hotel, view: :rooms, date: Date.current)

    within("#stay_view_room_#{room_type.id}_101") do
      click_link "Move or reassign"
    end

    within("#offcanvas_drawer") do
      expect(page).to have_content("Move or reassign stay")
      page.execute_script(<<~JS)
        document.querySelector('#booking_check_in').value = '#{Date.current.iso8601}'
        const room = document.querySelector('#booking_room_assignment')
        room.value = '#{room_type.id}|102'
        room.dispatchEvent(new Event('change', { bubbles: true }))
      JS
      click_button "Confirm move"
    end

    expect(page).to have_css("#stay_view_room_#{room_type.id}_102", text: "Ada Lovelace")
    expect(booking.reload.booking_rooms.first.room_number).to eq("102")
  end

  it "opens a cross-room drag proposal without mutation and confirms it through the existing command" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)

    drag_booking(room_number: "102", day_delta: 1)

    within("#offcanvas_drawer") do
      expect(page).to have_content("Move or reassign stay")
      expect(find("#booking_check_in", visible: :all).value).to eq((Date.current + 1.day).iso8601)
      expect(find("#booking_room_assignment", visible: :all).value).to eq("#{room_type.id}|102")
    end
    expect(booking.reload.check_in.to_date).to eq(Date.current)
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")

    within("#offcanvas_drawer") { click_button "Confirm move" }

    expect(page).to have_css("#stay_view_room_#{room_type.id}_102 #stay_view_booking_room_#{booking.booking_rooms.sole.id}")
    expect(booking.reload.check_in.to_date).to eq(Date.current + 1.day)
    expect(booking.booking_rooms.first.reload.room_number).to eq("102")
  end

  it "resizes either visible booking edge through date proposals" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current - 1.day, days: 7)

    drag_booking(room_number: "101", day_delta: 1, edge: "start")
    within("#offcanvas_drawer") do
      expect(page).to have_content("Change stay dates")
      expect(find("#booking_check_in", visible: :all).value).to eq((Date.current + 1.day).iso8601)
      expect(find("#booking_check_out", visible: :all).value).to eq((Date.current + 2.days).iso8601)
      click_button "Save dates"
    end
    expect(booking.reload.check_in.to_date).to eq(Date.current + 1.day)
    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 2)

    drag_booking(room_number: "101", day_delta: 1, edge: "end")
    within("#offcanvas_drawer") do
      expect(find("#booking_check_out", visible: :all).value).to eq((Date.current + 3.days).iso8601)
      click_button "Save dates"
    end
    expect(booking.reload.check_out.to_date).to eq(Date.current + 3.days)
  end

  it "uses long-press for touch drag while an early swipe cancels activation" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)
    segment_id = "stay_view_booking_room_#{booking.booking_rooms.sole.id}"

    dispatch_pointer_down(segment_id:, pointer_type: "touch")
    dispatch_pointer_finish(room_number: "102", day_delta: 1)
    expect(page).to have_no_css("#offcanvas_drawer", text: "Move or reassign stay", visible: :visible)

    dispatch_pointer_down(segment_id:, pointer_type: "touch")
    sleep 0.4
    dispatch_pointer_finish(room_number: "102", day_delta: 0)

    within("#offcanvas_drawer") do
      expect(page).to have_content("Move or reassign stay")
      click_button "Cancel"
    end
    expect(booking.reload.booking_rooms.first.room_number).to eq("101")
  end

  it "cancels an active drag with Escape without opening a proposal" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)
    segment_id = "stay_view_booking_room_#{booking.booking_rooms.sole.id}"
    find("##{segment_id}").hover
    expect(page).to have_css("##{segment_id}-panel", visible: :visible)
    dispatch_pointer_down(segment_id:)

    page.execute_script(<<~JS)
      (() => {
        const pointer = window.phaseFivePointer
        window.dispatchEvent(new PointerEvent("pointermove", {
          bubbles: true, cancelable: true, pointerId: pointer.pointerId, pointerType: pointer.pointerType,
          isPrimary: true, button: 0, clientX: pointer.x + 40, clientY: pointer.y
        }))
      })()
    JS

    expect(page).to have_css(".panel-timeline__segment-proposal .panel-timeline__segment-content > span", count: 2)
    expect(page).to have_css(".panel-timeline__segment-proposal", text: "Ada Lovelace")
    expect(page).to have_css(".panel-timeline__segment-proposal", text: "Confirmed")
    expect(page).to have_no_css("##{segment_id}-panel", visible: :visible)

    page.execute_script('window.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Escape" }))')

    expect(page).to have_no_css(".panel-timeline__segment-proposal")
    expect(page).to have_no_css("#offcanvas_drawer", text: "Move or reassign stay", visible: :visible)
    expect(booking.reload.check_in.to_date).to eq(Date.current)
  end

  it "treats unchanged and outside drops as cancellations" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)
    segment_id = "stay_view_booking_room_#{booking.booking_rooms.sole.id}"

    drag_booking(room_number: "101", day_delta: 0)
    expect(page).to have_no_css("#offcanvas_drawer", text: "Move or reassign stay", visible: :visible)

    dispatch_pointer_down(segment_id:)
    page.execute_script(<<~JS)
      (() => {
        const pointer = window.phaseFivePointer
        window.dispatchEvent(new PointerEvent("pointermove", {
          bubbles: true, cancelable: true, pointerId: pointer.pointerId, pointerType: pointer.pointerType,
          isPrimary: true, button: 0, clientX: 4, clientY: 4
        }))
        window.dispatchEvent(new PointerEvent("pointerup", {
          bubbles: true, cancelable: true, pointerId: pointer.pointerId, pointerType: pointer.pointerType,
          isPrimary: true, button: 0, clientX: 4, clientY: 4
        }))
      })()
    JS

    expect(page).to have_no_css(".panel-timeline__segment-proposal")
    expect(page).to have_no_css("#offcanvas_drawer", text: "Move or reassign stay", visible: :visible)
    expect(booking.reload.booking_rooms.first.room_number).to eq("101")
  end

  it "preserves timeline scroll and restores focus to the moved segment after a selective refresh" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 30)
    page.execute_script("document.getElementById('stay-view-timeline').scrollLeft = 20")

    drag_booking(room_number: "102", day_delta: 0)
    within("#offcanvas_drawer") { click_button "Confirm move" }

    trigger_id = "stay_view_booking_room_#{booking.booking_rooms.sole.id}-trigger"
    expect(page).to have_css("##{trigger_id}", wait: 10)
    expect(page).to have_css("##{trigger_id}:focus", wait: 2)
    expect(page.evaluate_script("document.getElementById('stay-view-timeline').scrollLeft")).to be_within(2).of(20)

    refresh

    expect(page).to have_css("##{trigger_id}", wait: 10)
    expect(page).to have_no_css("##{trigger_id}:focus")
  end

  it "keeps room-type and footer summaries aligned while sticky headings and footer hold their positions" do
    room_type.update!(room_numbers: (101..114).map(&:to_s))
    create(
      :room_type,
      hotel:,
      name: "Suites",
      room_number_mode: "custom",
      room_numbers: (201..220).map(&:to_s)
    )

    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 14)
    expect(page).to have_css(".panel-timeline__group-heading", count: 2)

    sticky_geometry = page.evaluate_script(<<~JS)
      (() => {
        const timeline = document.getElementById("stay-view-timeline")
        timeline.scrollLeft = 240
        timeline.scrollTop = 120

        const header = timeline.querySelector(".panel-timeline__header")
        const heading = timeline.querySelector(".panel-timeline__group-heading")
        const date = timeline.querySelector(".panel-timeline__date")
        const summary = timeline.querySelector("[data-slot='timeline-group-summary']")
        const footer = timeline.querySelector("[data-slot='timeline-footer']")
        const footerSummary = timeline.querySelector("[data-slot='timeline-footer-summary']")
        const headerRect = header.getBoundingClientRect()
        const headingRect = heading.getBoundingClientRect()
        const timelineRect = timeline.getBoundingClientRect()

        return {
          headingTop: headingRect.top,
          headerBottom: headerRect.bottom,
          dateLeft: date.getBoundingClientRect().left,
          summaryLeft: summary.getBoundingClientRect().left,
          footerSummaryLeft: footerSummary.getBoundingClientRect().left,
          footerBottom: footer.getBoundingClientRect().bottom,
          timelineBottom: timelineRect.bottom
        }
      })()
    JS

    expect(sticky_geometry.fetch("headingTop")).to be_within(2).of(sticky_geometry.fetch("headerBottom"))
    expect(sticky_geometry.fetch("summaryLeft")).to be_within(1).of(sticky_geometry.fetch("dateLeft"))
    expect(sticky_geometry.fetch("footerSummaryLeft")).to be_within(1).of(sticky_geometry.fetch("dateLeft"))
    expect(sticky_geometry.fetch("footerBottom")).to be_within(2).of(sticky_geometry.fetch("timelineBottom"))

    release_geometry = page.evaluate_script(<<~JS)
      (() => {
        const timeline = document.getElementById("stay-view-timeline")
        const header = timeline.querySelector(".panel-timeline__header")
        const headings = timeline.querySelectorAll(".panel-timeline__group-heading")
        const timelineTop = timeline.getBoundingClientRect().top
        const secondNaturalTop = timeline.scrollTop + headings[1].getBoundingClientRect().top - timelineTop
        timeline.scrollTop = secondNaturalTop

        const first = headings[0].getBoundingClientRect()
        const second = headings[1].getBoundingClientRect()
        return {
          firstBottom: first.bottom,
          secondTop: second.top,
          headerBottom: header.getBoundingClientRect().bottom
        }
      })()
    JS

    expect(release_geometry.fetch("firstBottom")).to be <= release_geometry.fetch("secondTop") + 1
    expect(release_geometry.fetch("secondTop")).to be_within(2).of(release_geometry.fetch("headerBottom"))
  end

  it "auto-applies filters, start date, and duration through the board frame" do
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
    create(:room_status, hotel:, room_type:, room_number: "102", status: "ready")
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 14)

    expect(page).to have_css(
      "[data-slot='stay-view-inventory-badge']" \
      "[aria-label='1 available room for #{room_type.name} on #{I18n.l(Date.current, format: :long)}']",
      text: "1"
    )
    expect(page).to have_css(
      "[data-slot='stay-view-footer-available']" \
      "[aria-label='1 available room on #{I18n.l(Date.current, format: :long)}']",
      text: "1"
    )
    expect(page).to have_css("[data-slot='stay-view-footer-occupancy']", text: "50%")

    find("#physical_status-trigger").click
    find("#physical_status-option-2", text: "Dirty").click

    expect(page).to have_css("#stay_view_room_#{room_type.id}_101")
    expect(page).to have_no_css("#stay_view_room_#{room_type.id}_102")
    expect(URI.parse(page.current_url).query).to include("physical_status=dirty")
    expect(page).to have_css(
      "[data-slot='stay-view-inventory-badge']" \
      "[aria-label='0 available rooms for #{room_type.name} on #{I18n.l(Date.current, format: :long)}']",
      text: "0"
    )
    expect(page).to have_css(
      "[data-slot='stay-view-footer-available']" \
      "[aria-label='0 available rooms on #{I18n.l(Date.current, format: :long)}']",
      text: "0"
    )
    expect(page).to have_css("[data-slot='stay-view-footer-occupancy']", text: "100%")

    find("#physical_status-trigger").click
    find("#physical_status-option-0", text: "All physical statuses").click
    expect(page).to have_css("#stay_view_room_#{room_type.id}_102")
    expect(page).to have_css(
      "[data-slot='stay-view-inventory-badge']" \
      "[aria-label='1 available room for #{room_type.name} on #{I18n.l(Date.current, format: :long)}']"
    )
    expect(page).to have_css("[data-slot='stay-view-footer-available']", text: "1")
    expect(page).to have_css("[data-slot='stay-view-footer-occupancy']", text: "50%")

    find("#days-trigger").click
    find("#days-option-0", text: "7 days").click
    expect(URI.parse(page.current_url).query).to include("days=7")

    page.execute_script(<<~JS)
      const startDate = document.querySelector('#start_date')
      startDate.value = '#{(Date.current + 7.days).iso8601}'
      startDate.dispatchEvent(new Event('change', { bubbles: true }))
    JS
    expect(page).to have_css("#stay-view-timeline[aria-label*='July 23, 2026']", wait: 10)
    expect(URI.parse(page.current_url).query).to include("start_date=#{(Date.current + 7.days).iso8601}")
  end

  it "keeps authorized standard rates aligned through Turbo filter updates" do
    permission = Permission.find_or_create_by!(slug: "manage_rates") { |record| record.name = "Manage Rates" }
    RolePermission.find_or_create_by!(role:, permission:)
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
    create(:room_status, hotel:, room_type:, room_number: "102", status: "ready")
    master_plan = room_type.rate_plans.order(:id).first
    create(:room_rate, room_type:, rate_plan: master_plan, date: Date.current, price: 145, currency: master_plan.currency)

    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 14)

    expect(page).to have_css("[data-slot='stay-view-standard-rate']", text: "145.00")
    find("#physical_status-trigger").click
    find("#physical_status-option-2", text: "Dirty").click
    expect(page).to have_css("#stay_view_room_#{room_type.id}_101")
    expect(page).to have_no_css("#stay_view_room_#{room_type.id}_102")
    expect(page).to have_css("[data-slot='stay-view-standard-rate']", text: "145.00")

    alignment = page.evaluate_script(<<~JS)
      (() => {
        const timeline = document.getElementById("stay-view-timeline")
        timeline.scrollLeft = 240
        const rate = timeline.querySelector("[data-slot='stay-view-standard-rate']")
        const summary = rate.closest("[data-slot='timeline-group-summary']")
        const date = timeline.querySelector(".panel-timeline__date")
        return {
          summaryLeft: summary.getBoundingClientRect().left,
          dateLeft: date.getBoundingClientRect().left,
          rateInside: rate.getBoundingClientRect().left >= summary.getBoundingClientRect().left &&
            rate.getBoundingClientRect().right <= summary.getBoundingClientRect().right
        }
      })()
    JS

    expect(alignment.fetch("summaryLeft")).to be_within(1).of(alignment.fetch("dateLeft"))
    expect(alignment.fetch("rateInside")).to be(true)
  end
end
