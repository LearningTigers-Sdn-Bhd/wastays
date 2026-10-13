# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Edit dates estimate", type: :system, js: true, frozen_time: Time.zone.local(2026, 7, 16, 10) do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live", accounting_business_date: Date.current) }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "front_desk", name: "Front Desk") }
  let(:room_type) { create(:room_type, hotel:, base_price: 100, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102]) }
  let!(:booking) do
    create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 3.days,
                     manual_rate_override: 300, total_amount: 300).tap do |record|
      create(:booking_room, booking: record, room_type:, room_number: "101", rate_plan: room_type.standard_rate_plan, subtotal: 300)
    end
  end

  before do
    %w[view_bookings manage_bookings].each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_through_ui(user)
  end

  it "quotes a dragged-shorter stay when the Sheet opens, not the current total" do
    visit hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)
    segment_id = "stay_view_booking_room_#{booking.booking_rooms.sole.id}"
    expect(page).to have_css("##{segment_id}[data-dates-url]", wait: 10)

    # What Stay View's interaction controller does at the end of a resize drag.
    page.execute_script(<<~JS)
      (() => {
        const url = new URL(document.getElementById(#{segment_id.to_json}).dataset.datesUrl, window.location.origin)
        url.searchParams.set("booking[check_in]", #{Date.current.iso8601.to_json})
        url.searchParams.set("booking[check_out]", #{(Date.current + 2.days).iso8601.to_json})
        document.getElementById("booking_action_sheet").src = url.toString()
      })()
    JS

    expect(page).to have_css("dialog#booking-dates-sheet[open]", text: "Check the proposed stay dates", wait: 10)
    expect(page).to have_css("[data-booking-actions--stay-price-target='calculationStatus']", text: "Estimate updated", wait: 10)
    expect(page).to have_css("[data-booking-actions--stay-price-target='roomTotal']", text: "200.00")
  end
end
