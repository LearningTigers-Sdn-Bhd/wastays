# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel booking creation sheet", type: :system, js: true, frozen_time: Time.zone.local(2026, 7, 23, 10) do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live", accounting_business_date: Date.current) }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "front_desk", name: "Front Desk") }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102]) }
  let!(:rate_plan) { create(:rate_plan, room_type:, name: "Flexible Rate") }

  before do
    %w[view_bookings manage_bookings].each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_through_ui(user)
    visit hotel_front_desk_path(hotel)
    open_booking_sheet
    select_room_type
  end

  def open_booking_sheet
    path = hotel_booking_action_quick_booking_path(hotel)
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

  def select_room_type
    set_native_value("[data-role='room-type'] select", room_type.id)
    expect(page).to have_css("[data-role='rate-plan'] select option[value='#{rate_plan.id}']", visible: :all)
    expect(page).to have_css("[data-role='room-number'] select option[value='101']", visible: :all)
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

  def selected_value(role)
    page.evaluate_script("document.querySelector(\"[data-role='#{role}'] select\").value")
  end

  def change_stay(check_in:, check_out:)
    page.execute_script(<<~JS)
      (() => {
        const host = document.querySelector("[data-controller~='booking-room-rows']")
        host.querySelector("[data-booking-room-rows-target='checkIn']").value = #{check_in.to_s.to_json}
        host.querySelector("[data-booking-room-rows-target='checkOut']").value = #{check_out.to_s.to_json}
        window.Stimulus.getControllerForElementAndIdentifier(host, "booking-room-rows").stayChanged()
      })()
    JS
  end

  it "preserves the selected room and rate plan when both remain available" do
    set_native_value("[data-role='rate-plan'] select", rate_plan.id)
    set_native_value("[data-role='room-number'] select", "101")

    change_stay(check_in: Date.current + 2.days, check_out: Date.current + 4.days)

    expect(page).to have_css("[data-role='room-number'] select option[value='101']", visible: :all)
    expect(selected_value("room-number")).to eq("101")
    expect(selected_value("rate-plan")).to eq(rate_plan.id.to_s)
    expect(page).to have_no_css("#toast-viewport .toast[data-variant='error']")
  end

  it "clears an unavailable room, preserves the rate plan, and alerts the user" do
    set_native_value("[data-role='rate-plan'] select", rate_plan.id)
    set_native_value("[data-role='room-number'] select", "101")
    unavailable_check_in = Date.current + 2.days
    unavailable_check_out = Date.current + 4.days
    create(:booking, hotel:, check_in: unavailable_check_in, check_out: unavailable_check_out).tap do |booking|
      create(:booking_room, booking:, room_type:, room_number: "101")
    end

    change_stay(check_in: unavailable_check_in, check_out: unavailable_check_out)

    expect(page).to have_css("#toast-viewport .toast[data-variant='error'][role='alert']", text: "Room 101 is no longer available")
    expect(selected_value("room-number")).to eq("")
    expect(selected_value("rate-plan")).to eq(rate_plan.id.to_s)
  end

  it "clears an unavailable rate plan, preserves the room, and alerts the user" do
    set_native_value("[data-role='rate-plan'] select", rate_plan.id)
    set_native_value("[data-role='room-number'] select", "101")
    rate_plan.destroy!

    change_stay(check_in: Date.current + 2.days, check_out: Date.current + 4.days)

    expect(page).to have_css("#toast-viewport .toast[data-variant='error'][role='alert']", text: "Flexible Rate")
    expect(selected_value("room-number")).to eq("101")
    expect(selected_value("rate-plan")).to eq("")
  end
end
