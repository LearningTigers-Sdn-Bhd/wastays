# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal booking transactions", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  before do
    user = create(:user)
    role = create(:role, account: hotel.account)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the shared new-booking offcanvas from the transaction endpoint" do
    get hotel_booking_transaction_new_booking_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
    expect(response.body).to include("New booking")
    expect(response.body).to include('type="datetime-local"')
  end

  it "reuses stay details for backdated walk-ins and places the override reason before internal notes" do
    get hotel_booking_transaction_backdated_check_in_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body.scan("Stay Details").size).to eq(1)
    expect(response.body).not_to include("Backdated check in Details")
    expect(response.body.index("Override Reason")).to be < response.body.index("Internal Notes")
  end

  it "renders the same amend-stay sheet independently of its launcher" do
    booking = create(:booking, hotel: hotel)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    get hotel_booking_transaction_amend_stay_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Edit Stay &amp; Room")
    expect(response.body).to include(hotel_booking_transaction_amend_stay_path(hotel, booking))
  end

  it "renders action-specific timeline sheets" do
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    get hotel_booking_transaction_edit_booking_timeline_path(hotel, booking),
      params: { timeline_action: "move", check_in: Date.current + 1.day, room_type_id: room_type.id, room_number: "101" },
      headers: { "Turbo-Frame" => "offcanvas_drawer" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Move Stay", "Confirm Move", "The current stay duration will be preserved.")

    get hotel_booking_transaction_edit_booking_timeline_path(hotel, booking),
      params: { timeline_action: "extend", check_out: Date.current + 3.days },
      headers: { "Turbo-Frame" => "offcanvas_drawer" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Extend Stay", "Confirm Extension")
  end

  it "rejects unknown timeline actions" do
    booking = create(:booking, hotel: hotel)

    get hotel_booking_transaction_edit_booking_timeline_path(hotel, booking), params: { timeline_action: "unknown" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "moves a timeline booking while preserving its duration" do
    second_room_type = create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "202" ])
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    patch hotel_booking_transaction_edit_booking_timeline_path(hotel, booking), params: {
      timeline_action: "move",
      booking: { check_in: Date.current + 3.days, room_type_id: second_room_type.id, room_number: "202" }
    }

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(booking.reload.check_in.to_date).to eq(Date.current + 3.days)
    expect(booking.check_out.to_date).to eq(Date.current + 5.days)
    expect(booking.booking_rooms.first).to have_attributes(room_type_id: second_room_type.id, room_number: "202")
  end

  it "extends a timeline booking and rejects shortening it" do
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    patch hotel_booking_transaction_edit_booking_timeline_path(hotel, booking), params: {
      timeline_action: "extend", booking: { check_out: Date.current + 4.days }
    }
    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(booking.reload.check_out.to_date).to eq(Date.current + 4.days)

    patch hotel_booking_transaction_edit_booking_timeline_path(hotel, booking), params: {
      timeline_action: "extend", booking: { check_out: Date.current + 3.days }
    }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("New check-out must be later than the current check-out.")
    expect(booking.reload.check_out.to_date).to eq(Date.current + 4.days)
  end

  it "keeps a timeline move unchanged when the destination room is unavailable" do
    room_type.update!(room_numbers: [ "101", "102" ])
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "102", status: "ready")
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    occupied_booking = create(:booking, hotel: hotel, check_in: Date.current + 3.days, check_out: Date.current + 5.days)
    create(:booking_room, booking: occupied_booking, room_type: room_type, room_number: "102")

    patch hotel_booking_transaction_edit_booking_timeline_path(hotel, booking), params: {
      timeline_action: "move",
      booking: { check_in: Date.current + 3.days, room_type_id: room_type.id, room_number: "102" }
    }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Room 102 is not available")
    expect(booking.reload.check_in.to_date).to eq(Date.current)
    expect(booking.booking_rooms.first.room_number).to eq("101")
  end

  it "completes timeline edits back to the booking board" do
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    return_to = board_hotel_bookings_path(hotel, start_date: Date.current)

    patch hotel_booking_transaction_edit_booking_timeline_path(hotel, booking), params: {
      timeline_action: "extend",
      return_to: return_to,
      booking: { check_out: Date.current + 3.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("complete_offcanvas")
    expect(response.body).to include(return_to)
  end

  it "keeps guest fields out of amend-stay updates" do
    booking = create(:booking, hotel: hotel, guest_name: "Original Guest", adults: 1)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    patch hotel_booking_transaction_amend_stay_path(hotel, booking), params: {
      booking: { guest_name: "Wrong Transaction", adults: 2 }
    }

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(booking.reload).to have_attributes(guest_name: "Original Guest", adults: 2)
  end

  it "keeps stay fields out of edit-booking updates" do
    booking = create(:booking, hotel: hotel, guest_name: "Original Guest", check_in: Date.current)
    original_check_in = booking.check_in

    patch hotel_booking_transaction_edit_booking_path(hotel, booking), params: {
      booking: { guest_name: "Updated Guest", check_in: Date.current + 3.days }
    }

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(booking.reload).to have_attributes(guest_name: "Updated Guest", check_in: original_check_in)
  end

  it "synchronizes the primary guest and records an audit log for booking-detail edits" do
    booking = create(:booking, hotel: hotel, guest_name: "Original Guest", guest_email: "guest@example.com")
    guest = create(:guest, name: "Original Guest", email: booking.guest_email)
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)

    expect {
      patch hotel_booking_transaction_edit_booking_path(hotel, booking), params: {
        booking: { guest_name: "Updated Guest", guest_email: booking.guest_email }
      }
    }.to change { BookingAuditLog.where(auditable: booking, action_type: "update").count }.by(1)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(booking.reload.primary_guest).to have_attributes(name: "Updated Guest", email: booking.guest_email)
  end

  it "renders validation errors in the edit-booking offcanvas" do
    booking = create(:booking, hotel: hotel)

    patch hotel_booking_transaction_edit_booking_path(hotel, booking), params: {
      booking: { guest_name: "" }
    }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Booking details could not be updated.")
    expect(response.body).to include("Guest name can&#39;t be blank")
    expect(booking.reload.guest_name).to be_present
  end

  it "creates and immediately checks in a walk-in booking" do
    expect {
      post hotel_booking_transaction_walk_in_check_in_path(hotel), params: {
        booking: {
          guest_name: "Walk In Guest",
          guest_email: "walk-in@example.com",
          guest_phone: "+60123456789",
          check_in: Date.current,
          check_out: Date.current + 1.day,
          adults: 1,
          room_type_id: room_type.id,
          room_number: "101"
        }
      }
    }.to change(Booking, :count).by(1)

    expect(Booking.last).to be_checked_in
    expect(response).to redirect_to(hotel_booking_path(hotel, Booking.last))
  end

  it "requires a reason before backdating an existing reservation check-in" do
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.yesterday)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    post hotel_booking_transaction_booking_backdated_check_in_path(hotel, booking), params: {
      booking: { checked_in_at: 1.day.ago }
    }

    expect(response).to have_http_status(:redirect)
    expect(booking.reload.status).to eq("confirmed")
  end

  it "renders check-in, checkout, late-checkout, reinstate, and cancellation sheets" do
    confirmed = create(:booking, hotel: hotel, status: "confirmed")
    checked_in = create(:booking, hotel: hotel, status: "checked_in")
    no_show = create(:booking, hotel: hotel, status: "no_show")
    [ confirmed, checked_in, no_show ].each { |booking| create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }
    create(:booking_folio, booking: checked_in, hotel: hotel, status: "open")

    [
      hotel_booking_transaction_check_in_reservation_path(hotel, confirmed),
      hotel_booking_transaction_check_out_path(hotel, checked_in),
      hotel_booking_transaction_late_checkout_path(hotel, checked_in),
      hotel_booking_transaction_reinstate_no_show_path(hotel, no_show),
      hotel_booking_transaction_cancel_booking_path(hotel, confirmed)
    ].each do |path|
      get path, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success), path
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"'), path
    end
  end

  it "renders security deposit collection in the check-in sheet" do
    booking = create(:booking, hotel: hotel, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    get hotel_booking_transaction_check_in_reservation_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response.body).to include("Collect security deposit")
    expect(response.body).to include("security_deposit_amount")
  end

  it "requires and audits a cancellation reason" do
    booking = create(:booking, hotel: hotel, status: "confirmed")

    post cancel_hotel_booking_path(hotel, booking), params: { cancellation_reason: "" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(booking.reload.status).to eq("confirmed")

    post cancel_hotel_booking_path(hotel, booking), params: { cancellation_reason: "Guest requested cancellation" }
    expect(booking.reload.status).to eq("cancelled")
    expect(BookingAuditLog.where(auditable: booking, action_type: "cancel").last.metadata).to include(
      "reason" => "Guest requested cancellation"
    )
  end
end
