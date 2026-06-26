# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal booking transactions", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
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

  it "reuses stay details for backdated walk-ins and places the reason details before internal notes" do
    get hotel_booking_transaction_backdated_check_in_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Stay and Backdated Details")
    expect(response.body.index("Reason Details")).to be < response.body.index("Internal Notes")
  end

  it "displays the backdated check-in warning banner, reason category select, and posting date in the form" do
    get hotel_booking_transaction_backdated_check_in_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Backdated check-in")
    expect(response.body).to include("uses a past arrival date. It may affect occupancy, folio charges, revenue reports, and audit logs. Reason is required.")
    expect(response.body).to include("Backdate Reason")
    expect(response.body).to include("Posting Date")
    expect(response.body).to include("Actual Check-In")
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

  it "does not mutate a booking when rendering a timeline move proposal" do
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days)
    booking_room = create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    original_check_in = booking.check_in
    original_check_out = booking.check_out

    expect {
      get hotel_booking_transaction_edit_booking_timeline_path(hotel, booking),
        params: { timeline_action: "move", check_in: Date.current + 1.day, room_type_id: room_type.id, room_number: "102" },
        headers: { "Turbo-Frame" => "offcanvas_drawer" }
    }.not_to change { BookingAuditLog.where(auditable: booking, action_type: "update").count }

    expect(response).to have_http_status(:success)
    expect(booking.reload).to have_attributes(check_in: original_check_in, check_out: original_check_out)
    expect(booking_room.reload.room_number).to eq("101")
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

  it "shows no-show review actions in the edit-booking offcanvas" do
    booking = create(:booking, hotel: hotel, status: "review_no_show", no_show_review_business_date: Date.current)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    get hotel_booking_transaction_edit_booking_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Backdated Check-in")
    expect(response.body).to include("Mark No-show")
    expect(response.body).to include(hotel_booking_transaction_mark_no_show_path(hotel, booking))
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
    expect(Booking.last.booking_folio).to be_present
    expect(BookingFolio.where(booking: Booking.last).count).to eq(1)
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

  it "renders check-in, checkout, late-checkout, no-show review, reinstate, and cancellation sheets" do
    confirmed = create(:booking, hotel: hotel, status: "confirmed")
    checked_in = create(:booking, hotel: hotel, status: "checked_in")
    no_show = create(:booking, hotel: hotel, status: "no_show")
    review_no_show = create(:booking, hotel: hotel, status: "review_no_show", no_show_review_business_date: Date.current)
    [ confirmed, checked_in, no_show, review_no_show ].each { |booking| create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }
    create(:booking_folio, booking: checked_in, hotel: hotel, status: "open")

    [
      hotel_booking_transaction_check_in_reservation_path(hotel, confirmed),
      hotel_booking_transaction_check_out_path(hotel, checked_in),
      hotel_booking_transaction_late_checkout_path(hotel, checked_in),
      hotel_booking_transaction_mark_no_show_path(hotel, review_no_show),
      hotel_booking_transaction_reinstate_no_show_path(hotel, no_show),
      hotel_booking_transaction_cancel_booking_path(hotel, confirmed)
    ].each do |path|
      get path, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success), path
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"'), path
    end
  end

  it "completes no-show finalization from the offcanvas" do
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: Date.current,
      check_in: Date.current,
      check_out: Date.current + 2.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 200.0)

    post mark_no_show_hotel_booking_path(hotel, booking),
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_offcanvas"')
    expect(response.body).to include(CGI.escapeHTML(hotel_booking_path(hotel, booking)))
    expect(booking.reload.status).to eq("no_show")
    expect(flash[:notice]).to include("Tourism tax was not charged")
  end

  it "renders and completes an audited no-show tourism-tax repair" do
    grant_permission(role, "post_folio_corrections")
    booking = create(:booking, hotel: hotel, status: "no_show", currency: "MYR")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "tax",
      amount: 10,
      metadata: {
        posting_source: "no_show",
        tax_line: { type: "tourism_tax", name: "Tourism Tax", amount: "10.00" }
      }
    )

    get hotel_booking_transaction_repair_no_show_folio_path(hotel, booking),
      headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Repair No-show Folio", "MYR 10.00", "This folio will close")

    post repair_no_show_folio_hotel_booking_path(hotel, booking),
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(flash[:notice]).to include("Tourism tax of MYR 10.00 was removed")
    expect(folio.reload).to be_closed
  end

  it "does not expose no-show folio repair without folio-correction permission" do
    booking = create(:booking, hotel: hotel, status: "no_show")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "tax",
      amount: 10,
      metadata: {
        posting_source: "no_show",
        tax_line: { type: "tourism_tax", amount: "10.00" }
      }
    )

    get hotel_booking_transaction_repair_no_show_folio_path(hotel, booking),
      headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:redirect)
  end

  it "re-renders no-show finalization errors in the offcanvas" do
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: Date.current,
      check_in: Date.current,
      check_out: Date.current + 2.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 200.0)
    start_business_date_audit(hotel)

    post mark_no_show_hotel_booking_path(hotel, booking),
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('action="update"')
    expect(response.body).to include('target="offcanvas_drawer"')
    expect(response.body).to include("No-show could not be confirmed.")
    expect(response.body).to include(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
    expect(booking.reload.status).to eq("review_no_show")
  end

  it "blocks manual no-show finalization while night audit is running" do
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: Date.current,
      check_in: Date.current,
      check_out: Date.current + 2.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 200.0)
    start_business_date_audit(hotel)

    post mark_no_show_hotel_booking_path(hotel, booking)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to eq(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
    expect(booking.reload.status).to eq("review_no_show")
    expect(booking.booking_folio).to be_nil
  end

  it "allows existing-reservation backdated check-in only during no-show review" do
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: Date.current,
      check_in: Date.current,
      check_out: Date.current + 1.day
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 100.0)

    post hotel_booking_transaction_booking_backdated_check_in_path(hotel, booking), params: {
      booking: { checked_in_at: Time.current },
      retroactive_reason: "Late arrival"
    }

    expect(booking.reload.status).to eq("checked_in")
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

  it "creates and immediately checks in a backdated walk-in booking with posting_date and reasons" do
    past_date = 1.day.ago.to_date
    create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")
    create(:hotel_business_date, hotel: hotel, business_date: past_date, status: "closed")
    signed_in_user = User.joins(:user_hotel_accesses).where(user_hotel_accesses: { hotel_id: hotel.id }).first
    user_role = signed_in_user.user_hotel_accesses.first.role
    grant_permission(user_role, "post_folio_charges")
    grant_permission(user_role, "post_folio_payments")
    grant_permission(user_role, "override_financial_date_lock")

    expect {
      post hotel_booking_transaction_backdated_check_in_path(hotel), params: {
        booking: {
          guest_name: "Backdated Walk In",
          guest_email: "backdated-walk-in@example.com",
          guest_phone: "+60123456789",
          check_in: past_date,
          check_out: Date.current,
          adults: 1,
          room_type_id: room_type.id,
          room_number: "101",
          record_payment: "1",
          payment_method: "cash",
          payment_amount: "250.00"
        },
        posting_date: past_date.to_s,
        backdate_reason: "Manual offline check-in",
        retroactive_reason: "Router was down"
      }
    }.to change(Booking, :count).by(1)

    booking = Booking.last
    expect(booking).to be_checked_in
    expect(response).to redirect_to(hotel_booking_path(hotel, booking))

    # Payment transaction captured_at must be override
    payment = booking.payment_transactions.last
    expect(payment.captured_at.to_date).to eq(past_date)

    # Catch-up charges posting date must be override
    folio = booking.booking_folio
    expect(folio.folio_transactions.charge.count).to be >= 1
    folio.folio_transactions.charge.each do |tx|
      expect(tx.posting_date).to eq(past_date)
    end

    # Audit log metadata
    log = BookingAuditLog.where(auditable: booking, action_type: "check_in").last
    expect(log.metadata["backdate_reason_category"]).to eq("Manual offline check-in")
    expect(log.metadata["backdate_reason_details"]).to eq("Router was down")
  end

  it "allows backdated check-in with a standard category and blank reason details" do
    past_date = 1.day.ago.to_date
    create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")
    create(:hotel_business_date, hotel: hotel, business_date: past_date, status: "closed")

    signed_in_user = User.joins(:user_hotel_accesses).where(user_hotel_accesses: { hotel_id: hotel.id }).first
    user_role = signed_in_user.user_hotel_accesses.first.role
    grant_permission(user_role, "post_folio_charges")
    grant_permission(user_role, "override_financial_date_lock")

    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: past_date,
      check_in: past_date,
      check_out: Date.current
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 100.0)

    post hotel_booking_transaction_booking_backdated_check_in_path(hotel, booking), params: {
      booking: { checked_in_at: past_date.to_time },
      backdate_reason: "System / internet issue",
      retroactive_reason: ""
    }

    expect(booking.reload.status).to eq("checked_in")
    expect(booking.booking_folio).to be_present
    expect(BookingFolio.where(booking: booking).count).to eq(1)
    log = BookingAuditLog.where(auditable: booking, action_type: "check_in").last
    expect(log.metadata["backdate_reason_category"]).to eq("System / internet issue")
    expect(log.metadata["backdate_reason_details"]).to be_blank
    expect(log.metadata["retroactive_reason"]).to eq("System / internet issue")
  end

  it "requires reason details when backdate_reason is Other" do
    past_date = 1.day.ago.to_date
    create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")

    signed_in_user = User.joins(:user_hotel_accesses).where(user_hotel_accesses: { hotel_id: hotel.id }).first
    user_role = signed_in_user.user_hotel_accesses.first.role
    grant_permission(user_role, "post_folio_charges")
    grant_permission(user_role, "override_financial_date_lock")

    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: past_date,
      check_in: past_date,
      check_out: Date.current
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 100.0)

    post hotel_booking_transaction_booking_backdated_check_in_path(hotel, booking), params: {
      booking: { checked_in_at: past_date.to_time },
      backdate_reason: "Other",
      retroactive_reason: ""
    }

    expect(response).to redirect_to(hotel_bookings_path(hotel))
    expect(flash[:alert]).to include("Please provide details for the backdated check-in reason")
    expect(booking.reload.status).to eq("review_no_show")
  end
end
