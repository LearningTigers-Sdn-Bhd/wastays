# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Choosing a travel agent on the New Booking sheet", type: :system, js: true, frozen_time: :business_day do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live", accounting_business_date: Date.current) }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "front_desk", name: "Front Desk") }

  before do
    create(:hotel_corporate_account, hotel:, account_type: "travel_agent")
    %w[view_bookings manage_bookings].each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_through_ui(user)
    visit hotel_front_desk_path(hotel)
    open_new_booking_sheet
  end

  def open_new_booking_sheet
    path = hotel_booking_action_new_booking_path(hotel)
    page.execute_script(<<~JS)
      (() => {
        const link = document.createElement("a")
        link.href = #{path.to_json}
        link.dataset.turboFrame = "booking_action_sheet"
        document.body.appendChild(link)
        link.click()
        link.remove()
      })()
    JS
    expect(page).to have_css("dialog#booking-creation-sheet", visible: :visible)
  end

  def set_native_value(selector, value)
    page.execute_script(<<~JS)
      (() => {
        const input = document.querySelector(#{selector.to_json})
        input.value = #{value.to_s.to_json}
        input.dispatchEvent(new Event("change", { bubbles: true }))
      })()
    JS
  end

  it "swaps Bill to for the agent picker while Travel Agent is the source of a reservation" do
    expect(page).to have_no_field("Travel agent", visible: :visible)
    expect(page).to have_css("[data-booking-room-rows-target='billTo']", visible: :visible)

    set_native_value("select[name='booking[source]']", "travel_agent")

    expect(page).to have_css("[data-booking-room-rows-target='travelAgent']", visible: :visible)
    expect(page).to have_content("Room charges bill to the travel agent chosen under Booking source.")
    expect(page).to have_no_css("[data-booking-room-rows-target='billTo']", visible: :visible)

    set_native_value("select[name='booking[booking_type]']", "walk_in")

    expect(page).to have_no_css("[data-booking-room-rows-target='travelAgent']", visible: :visible)
    expect(page).to have_css("[data-booking-room-rows-target='billTo']", visible: :visible)

    set_native_value("select[name='booking[booking_type]']", "reservation")
    set_native_value("select[name='booking[source]']", "phone")

    expect(page).to have_no_css("[data-booking-room-rows-target='travelAgent']", visible: :visible)
    expect(page).to have_css("[data-booking-room-rows-target='billTo']", visible: :visible)
  end
end
