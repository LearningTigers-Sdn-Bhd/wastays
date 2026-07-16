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

  it "auto-applies filters, start date, and duration through the board frame" do
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
    create(:room_status, hotel:, room_type:, room_number: "102", status: "ready")
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 14)

    find("#physical_status-trigger").click
    find("#physical_status-option-2", text: "Dirty").click

    expect(page).to have_css("#stay_view_room_#{room_type.id}_101")
    expect(page).to have_no_css("#stay_view_room_#{room_type.id}_102")
    expect(URI.parse(page.current_url).query).to include("physical_status=dirty")

    find("#physical_status-trigger").click
    find("#physical_status-option-0", text: "All physical statuses").click
    expect(page).to have_css("#stay_view_room_#{room_type.id}_102")

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
end
