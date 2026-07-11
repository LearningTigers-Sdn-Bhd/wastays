# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal group checkout", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:group) { create(:group_booking, hotel: hotel, name: "ACME Group") }
  let!(:booking) { create(:booking, hotel: hotel, group_booking: group, group_position: 1, reservation_number: 104, status: "checked_in", check_in: hotel.current_business_date, check_out: hotel.current_business_date) }
  let!(:sibling) { create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 105, status: "checkout_required", check_in: hotel.current_business_date, check_out: hotel.current_business_date) }

  before do
    role.permissions << manage_bookings
    role.permissions << view_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders eligible group checkout targets in the left rail" do
    create_room_and_folio(booking, room_number: "203", room_type_name: "Deluxe King")
    create_room_and_folio(sibling, room_number: "204", room_type_name: "Twin Room")
    completed = create(:booking, hotel: hotel, group_booking: group, group_position: 3, reservation_number: 106, status: "completed")
    create_room_and_folio(completed, room_number: "205", room_type_name: "Suite")

    get hotel_booking_transaction_check_out_path(hotel, booking), headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Group Checkout", "Perform Checkout on:", "ACME Group")

    document = Nokogiri::HTML(response.body)
    selectable_ids = document.css('input[name="booking_ids[]"]:not([disabled])').map { |node| node["value"] }
    disabled_ids = document.css('input[name="booking_ids[]"][disabled]').map { |node| node["value"] }
    expect(selectable_ids).to contain_exactly(booking.id.to_s, sibling.id.to_s)
    expect(disabled_ids).to include(completed.id.to_s)
  end

  it "defaults eligible company folios to direct bill" do
    create_room_and_folio(booking, room_number: "203", room_type_name: "Deluxe King")
    relationship = create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:folio_transaction, booking_folio: company_folio, transaction_type: :charge, category: "accommodation", amount: 480)

    get hotel_booking_transaction_check_out_path(hotel, booking), headers: { "Accept" => "text/html" }

    document = Nokogiri::HTML(response.body)
    selected = document.at_css("select[name='checkout_bookings[#{booking.id}][folios][#{company_folio.id}][action]'] option[selected]")
    expect(selected["value"]).to eq("direct_bill")
  end

  it "rolls back all selected group checkouts when one selected booking fails" do
    create_room_and_folio(booking, room_number: "203", room_type_name: "Deluxe King")
    sibling_folio = create_room_and_folio(sibling, room_number: "204", room_type_name: "Twin Room")
    create(:folio_transaction, booking_folio: sibling_folio, transaction_type: :charge, category: "accommodation", amount: 100)

    post check_out_hotel_booking_path(hotel, booking), params: {
      checkout_sheet: "1",
      target_scope: "group",
      booking_ids: [ booking.id, sibling.id ],
      checked_out_at: "#{hotel.current_business_date}T12:00"
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to match(/Booking #.*10000105 \/ Twin Room - 204/)
    expect(response.body).to include("permission to post checkout payments")
    expect(booking.reload.status).to eq("checked_in")
    expect(sibling.reload.status).to eq("checkout_required")
  end

  it "posts distinct early departure charges per booking when both group members depart early" do
    role.permissions << Permission.find_or_create_by!(slug: "post_folio_payments") { |permission| permission.name = "Post Folio Payments" }
    role.permissions << Permission.find_or_create_by!(slug: "post_folio_charges") { |permission| permission.name = "Post Folio Charges" }

    booking.update!(check_out: hotel.current_business_date + 2.days)
    sibling.update_column(:status, "checked_in")
    sibling.update!(check_out: hotel.current_business_date + 1.day)
    booking_folio = create_room_and_folio(booking, room_number: "203", room_type_name: "Deluxe King")
    sibling_folio = create_room_and_folio(sibling, room_number: "204", room_type_name: "Twin Room")

    post check_out_hotel_booking_path(hotel, booking), params: {
      checkout_sheet: "1",
      target_scope: "group",
      booking_ids: [ booking.id, sibling.id ],
      checked_out_at: "#{hotel.current_business_date}T12:00",
      early_departures: {
        booking.id.to_s => { apply_charge: "true", charge_amount: "75.00" },
        sibling.id.to_s => { apply_charge: "true", charge_amount: "40.00" }
      },
      checkout_bookings: {
        booking.id.to_s => { folios: { booking_folio.id.to_s => { action: "pay_now", amount: "275.00" } } },
        sibling.id.to_s => { folios: { sibling_folio.id.to_s => { action: "pay_now", amount: "240.00" } } }
      }
    }

    expect(response).to redirect_to(%r{/booking-control-panels/#{booking.id}})
    expect(booking.reload.status).to eq("completed")
    expect(sibling.reload.status).to eq("completed")
    expect(booking_folio.reload.folio_transactions.find_by(category: "early_departure_charge").amount).to eq(75.0)
    expect(sibling_folio.reload.folio_transactions.find_by(category: "early_departure_charge").amount).to eq(40.0)
  end

  def create_room_and_folio(target_booking, room_number:, room_type_name:)
    room_type = create(:room_type, hotel: hotel, name: room_type_name)
    create(:booking_room, booking: target_booking, room_type: room_type, room_number: room_number)
    create(:booking_folio, booking: target_booking, hotel: hotel)
  end
end
