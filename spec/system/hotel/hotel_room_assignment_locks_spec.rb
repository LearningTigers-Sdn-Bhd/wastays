# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel Room Assignment Locks", type: :system do
  before do
    driven_by :cuprite
  end

  let(:hotel) { create(:hotel) }
  let(:user1) { create(:user, name: "Admin One") }
  let(:user2) { create(:user, name: "Admin Two") }
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

  it "prevents Admin Two from selecting a room already locked by Admin One" do
    # Admin One locks Room 206
    using_session("Admin One") do
      login_as(user1)
      visit hotel_booking_path(hotel, booking)

      find("button[onclick*='edit-stay-details-modal']").click
      expect(page).to have_css("#edit-stay-details-modal[open]", visible: :all)

      within("#edit-stay-details-modal") do
        expect(page).to have_select("Room Number", disabled: false)
        find("#booking_room_number").find(:option, "206").select_option
        execute_script("document.getElementById('booking_room_number').dispatchEvent(new Event('change', { bubbles: true }))")
      end
    end

    max_retries = 10
    retries = 0
    while retries < max_retries && !RoomLock.where(hotel: hotel, room_number: "206", user: user1).exists?
      sleep 0.5
      retries += 1
    end

    expect(RoomLock.where(hotel: hotel, room_number: "206", user: user1).exists?).to be true

    # Admin Two tries to lock Room 206
    using_session("Admin Two") do
      login_as(user2)
      visit hotel_booking_path(hotel, booking)

      find("button[onclick*='edit-stay-details-modal']").click
      expect(page).to have_css("#edit-stay-details-modal[open]", visible: :all)

      within("#edit-stay-details-modal") do
        expect(page).to have_select("Room Number", disabled: false)
        expect(page).to have_select("Room Number", with_options: [ "206 (Locked by another staff)" ])
        expect(page).to have_select("Room Number", with_options: [ "207" ])
        click_button "Cancel"
      end

      # Simulating a race condition via the Check-In modal (which uses text fields)
      click_button "Check In Guest"
      expect(page).to have_css("#check-in-modal-show-#{booking.id}[open]", visible: :all)

      within("#check-in-modal-show-#{booking.id}") do
        find("input[name*='room_number']").set "206"
        # Trigger change
        execute_script("document.querySelector('#check-in-modal-show-#{booking.id} [name*=\"room_number\"]').dispatchEvent(new Event('change', { bubbles: true }))")
      end

      sleep 2

      expect(page).to have_content("Room Already Occupied")
      expect(page).to have_content("Admin One")

      find("#room-lock-alert-close").click
      expect(page).not_to have_css("#room-lock-alert-modal[open]", visible: :all)
    end

    # Now Admin One releases the lock (closes modal)
    using_session("Admin One") do
      within("#edit-stay-details-modal") do
        click_button "Cancel"
      end
    end

    max_retries = 10
    retries = 0
    while retries < max_retries && RoomLock.count > 0
      sleep 0.5
      retries += 1
    end

    expect(RoomLock.count).to eq(0)

    using_session("Admin Two") do
      visit hotel_booking_path(hotel, booking)
      find("button[onclick*='edit-stay-details-modal']").click
      expect(page).to have_css("#edit-stay-details-modal[open]", visible: :all)

      within("#edit-stay-details-modal") do
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
    # Wait for dashboard or welcome message
    expect(page).to have_content(/Welcome|Dashboard/i)
  end
end
