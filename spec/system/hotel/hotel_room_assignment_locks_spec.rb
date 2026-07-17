# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel Room Assignment Locks", type: :system do
  before do
    driven_by :cuprite, options: { timeout: 10 }
  end

  let(:hotel) { create(:hotel) }
  let(:user1) { create(:user, account: hotel.account, name: "Admin One") }
  let(:user2) { create(:user, account: hotel.account, name: "Admin Two") }
  let!(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "206", "207" ]) }
  let!(:booking) { create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 2.days) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type) }

  before do
    role = create(:role, account: hotel.account)
    %w[view_bookings manage_bookings].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission
    end

    create(:user_hotel_access, user: user1, hotel: hotel, role: role)
    create(:user_hotel_access, user: user2, hotel: hotel, role: role)

    # Ensure room_type has inventory
    (Date.current..(Date.current + 5.days)).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, available_room_numbers: [ "206", "207" ])
    end
  end

  xit "prevents Admin Two from selecting a room already locked by Admin One" do
    # Admin One locks Room 206
    using_session("Admin One") do
      login_as(user1)
      visit hotel_booking_path(hotel, booking)

      click_link "Edit Stay"
      expect(page).to have_css("#offcanvas_drawer #booking_room_number")

      within("#offcanvas_drawer") do
        expect(page).to have_select("Room Number", disabled: false)
        find("#booking_room_number").find(:option, "206").select_option
        execute_script("document.getElementById('booking_room_number').dispatchEvent(new Event('change', { bubbles: true }))")
      end

      # Wait for lock to be persisted in DB
      max_wait = 10
      start_time = Time.current
      until RoomLock.where(hotel: hotel, room_type: room_type, room_number: "206", user: user1).exists? || (Time.current - start_time) > max_wait
        sleep 0.1
      end

      expect(RoomLock.where(hotel: hotel, room_type: room_type, room_number: "206", user: user1).exists?).to be true
    end

    # Admin Two tries to lock Room 206
    using_session("Admin Two") do
      login_as(user2)
      visit hotel_booking_path(hotel, booking)

      click_link "Edit Stay"
      expect(page).to have_css("#offcanvas_drawer #booking_room_number")

      within("#offcanvas_drawer") do
        expect(page).to have_select("Room Number", disabled: false)
        expect(page).to have_select("Room Number", with_options: [ "206 (Locked by another staff)" ])
        expect(page).to have_select("Room Number", with_options: [ "207" ])
      end

      # Simulating a race condition via the shared Check-In transaction sheet.
      page.execute_script("document.getElementById('offcanvas_drawer').src = '#{hotel_booking_transaction_check_in_reservation_path(hotel, booking)}'")
      expect(page).to have_css("#offcanvas_drawer select[name*='room_number']")

      within("#offcanvas_drawer") do
        # We need to set the room_type_id for the controller to work
        container = find("div[data-controller~='room-lock']", match: :first)
        execute_script("arguments[0].dataset.roomLockRoomTypeIdValue = '#{room_type.id}'", container)

        # Use JS to set value since it might not be in the select options due to the lock
        execute_script("document.querySelector('#offcanvas_drawer select[name*=\"room_number\"]').value = '206'")
        # Trigger change
        execute_script("document.querySelector('#offcanvas_drawer [name*=\"room_number\"]').dispatchEvent(new Event('change', { bubbles: true }))")
      end

      # Wait for the alert modal to be opened
      expect(page).to have_css("#room-lock-alert-modal[open]", visible: :all, wait: 5)

      within("#room-lock-alert-modal", visible: :all) do
        expect(page).to have_content("Room Already Occupied")
        expect(page).to have_content("Admin One")
      end

      find("#room-lock-alert-close").click
      expect(page).not_to have_css("#room-lock-alert-modal[open]", visible: :all)
    end

    # Now Admin One releases the lock (closes modal)
    using_session("Admin One") do
      execute_script("document.querySelector('[data-action=\"click->offcanvas#close\"]').click()")
    end

    max_retries = 50
    retries = 0
    while retries < max_retries && RoomLock.count > 0
      sleep 0.1
      retries += 1
    end

    expect(RoomLock.count).to eq(0)

    using_session("Admin Two") do
      visit hotel_booking_path(hotel, booking)
      click_link "Edit Stay"
      expect(page).to have_css("#offcanvas_drawer #booking_room_number")

      within("#offcanvas_drawer") do
        expect(page).to have_select("Room Number", disabled: false)
        expect(page).to have_select("Room Number", with_options: [ "206" ])
      end
    end
  end

  def login_as(user)
    visit login_path
    find("input[name*='email']").set user.email
    find("input[name*='password']").set "password123"
    click_button "Sign In to Portal"
    expect(page).to have_no_current_path(login_path, ignore_query: true)
  end
end
