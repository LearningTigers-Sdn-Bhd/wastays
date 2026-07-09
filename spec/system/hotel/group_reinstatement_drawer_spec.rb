# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group reinstatement drawer", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "group-reinstate@example.com") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:group) { create(:group_booking, hotel: hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: %w[101 102]) }
  let!(:first) { create_group_child(name: "First Guest", room_number: "101") }
  let!(:second) { create_group_child(name: "Second Guest", room_number: "102") }

  before do
    driven_by(:cuprite)
    %w[view_bookings manage_bookings].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |permission| permission.name = slug.humanize }
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"

    visit hotel_booking_control_panel_path(hotel, first, tab: "booking_details")
    page.execute_script("document.getElementById('offcanvas_drawer').src = '#{hotel_booking_transaction_reinstate_no_show_path(hotel, first)}'")
    expect(page).to have_css("#offcanvas_drawer_container.block", visible: :all)
  end

  it "shows the launched child and switches the same form between selected children" do
    within("#offcanvas_drawer") do
      expect(page).to have_checked_field("booking_ids[]", with: first.id.to_s)
      expect(page).to have_content("Configured")
      expect(page).to have_css("[data-group-lifecycle-targets-target='panel'][data-booking-id='#{first.id}']:not([hidden])")
      expect(page).to have_content(/scheduled stay/i)
      expect(page).to have_select("Room Category", selected: room_type.name)

      fill_in "Reason for Reinstatement", with: "Delayed group arrival"
      find("input[name='booking_ids[]'][value='#{second.id}']").click

      expect(page).to have_css("[data-group-lifecycle-targets-target='panel'][data-booking-id='#{second.id}']:not([hidden])")
      expect(page).to have_css("[data-group-lifecycle-targets-target='panel'][data-booking-id='#{first.id}'][hidden]", visible: :all)
      expect(page).to have_field("Reason for Reinstatement", with: "Delayed group arrival")
      expect(page).to have_content("Configured")
    end
  end

  def create_group_child(name:, room_number:)
    booking = create(:booking, hotel: hotel, group_booking: group, status: "no_show", guest_name: name)
    create(:booking_room, booking: booking, room_type: room_type, room_number: room_number)
    create(:booking_guest, booking: booking, guest: create(:guest, name: name), is_primary: true)
    booking
  end
end
