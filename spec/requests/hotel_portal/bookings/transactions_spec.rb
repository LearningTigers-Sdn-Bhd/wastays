# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal booking transactions", :business_day, type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def booking_details_path(booking, **params)
    hotel_booking_control_panel_path(hotel, booking, { tab: "booking_details" }.merge(params))
  end

  def create_group_child(group, status:, room_number:, guest_name: "Group Guest", room_type: nil)
    room_type ||= self.room_type
    attributes = { hotel: hotel, group_booking: group, status: status, guest_name: guest_name }
    attributes[:no_show_review_business_date] = Date.current if status == "review_no_show"
    booking = create(:booking, attributes)
    create(:booking_room, booking: booking, room_type: room_type, room_number: room_number, subtotal: 200.0)
    create(:booking_guest, booking: booking, guest: create(:guest, name: guest_name), is_primary: true)
    booking
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
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

  it "renders checkout, late-checkout, no-show review, and reinstate sheets" do
    checked_in = create(:booking, hotel: hotel, status: "checked_in")
    no_show = create(:booking, hotel: hotel, status: "no_show")
    review_no_show = create(:booking, hotel: hotel, status: "review_no_show", no_show_review_business_date: Date.current)
    [ checked_in, no_show, review_no_show ].each { |booking| create(:booking_room, booking: booking, room_type: room_type, room_number: "101") }
    create(:booking_folio, booking: checked_in, hotel: hotel, status: "open")

    [
      hotel_booking_transaction_check_out_path(hotel, checked_in),
      hotel_booking_transaction_late_checkout_path(hotel, checked_in),
      hotel_booking_transaction_mark_no_show_path(hotel, review_no_show),
      hotel_booking_transaction_reinstate_no_show_path(hotel, no_show)
    ].each do |path|
      get path, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success), path
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"'), path
    end
  end

  it "renders group target choices for late checkout" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "review_due_out", room_number: "101", guest_name: "Aina Guest")
    second = create_group_child(group, status: "checked_in", room_number: "102", guest_name: "Busy Guest")

    get hotel_booking_transaction_late_checkout_path(hotel, first), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Perform Late Checkout on:")
    expect(response.body).to include("101 - Aina Guest", "102 - Busy Guest")
    expect(response.body).to include("value=\"#{second.id}\" disabled=\"disabled\"")
  end

  it "resolves late checkout with a charge for selected group bookings atomically" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "review_due_out", room_number: "101", guest_name: "Aina Guest")
    second = create_group_child(group, status: "review_due_out", room_number: "102", guest_name: "Budi Guest")
    unselected = create_group_child(group, status: "review_due_out", room_number: "103", guest_name: "Chin Guest")
    [ first, second ].each { |booking| create(:booking_folio, booking: booking, hotel: hotel) }
    grant_permission(role, "post_folio_charges")

    post process_late_checkout_hotel_booking_path(hotel, first), params: {
      target_scope: "individual",
      booking_ids: [ first.id, second.id ],
      charge_type: "charge",
      amount: "50.00"
    }

    expect(response).to redirect_to(booking_details_path(first))
    expect(first.reload.status).to eq("checked_in")
    expect(second.reload.status).to eq("checked_in")
    expect(unselected.reload.status).to eq("review_due_out")
    expect(first.booking_folio.folio_transactions.find_by(category: "late_checkout_charge").amount).to eq(50.0)
    expect(second.booking_folio.folio_transactions.find_by(category: "late_checkout_charge").amount).to eq(50.0)
    expect(flash[:notice]).to eq("2 bookings resolved for late checkout.")
  end

  it "rejects late checkout for selected group bookings atomically" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "review_due_out", room_number: "101", guest_name: "Aina Guest")
    second = create_group_child(group, status: "review_due_out", room_number: "102", guest_name: "Budi Guest")

    post process_late_checkout_hotel_booking_path(hotel, first), params: {
      target_scope: "individual",
      booking_ids: [ first.id, second.id ],
      charge_type: "none"
    }

    expect(response).to redirect_to(booking_details_path(first))
    expect(first.reload.status).to eq("checkout_required")
    expect(second.reload.status).to eq("checkout_required")
    expect(flash[:notice]).to eq("2 bookings late checkout rejected.")
  end

  it "rejects a late-checkout group batch when a selected booking is no longer eligible" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "review_due_out", room_number: "101", guest_name: "Aina Guest")
    ineligible = create_group_child(group, status: "checked_in", room_number: "102", guest_name: "Busy Guest")

    post process_late_checkout_hotel_booking_path(hotel, first), params: {
      target_scope: "individual",
      booking_ids: [ first.id, ineligible.id ],
      charge_type: "none"
    }

    expect(response).to redirect_to(booking_details_path(first))
    expect(first.reload.status).to eq("review_due_out")
    expect(flash[:alert]).to include("no longer eligible")
  end

  it "backdated-checks-in selected no-show review group bookings atomically" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "review_no_show", room_number: "101", guest_name: "Aina Guest")
    second = create_group_child(group, status: "review_no_show", room_number: "102", guest_name: "Budi Guest")

    post hotel_booking_transaction_booking_backdated_check_in_path(hotel, first), params: {
      booking_ids: [ first.id, second.id ],
      target_scope: "individual",
      backdate_reason: "Manual offline check-in"
    }

    expect(response).to redirect_to(booking_details_path(first))
    expect(first.reload.status).to eq("checked_in")
    expect(second.reload.status).to eq("checked_in")
    expect(flash[:notice]).to eq("2 bookings backdated checked in.")
  end

  it "marks selected no-show review group bookings as no-show atomically with a shared reason" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "review_no_show", room_number: "101", guest_name: "Aina Guest")
    second = create_group_child(group, status: "review_no_show", room_number: "102", guest_name: "Budi Guest")
    unselected = create_group_child(group, status: "review_no_show", room_number: "103", guest_name: "Chin Guest")
    reason = "Group did not arrive before audit close"

    post mark_no_show_hotel_booking_path(hotel, first), params: { target_scope: "individual", booking_ids: [ first.id, second.id ], no_show_reason: reason }

    expect(response).to redirect_to(booking_details_path(first))
    expect(first.reload.status).to eq("no_show")
    expect(second.reload.status).to eq("no_show")
    expect(unselected.reload.status).to eq("review_no_show")
    audit_reasons = BookingAuditLog.where(
      auditable_type: "Booking",
      auditable_id: [ first.id, second.id ],
      action_type: "no_show"
    ).map { |audit| audit.metadata["reason"] }
    expect(audit_reasons).to contain_exactly(reason, reason)
    expect(flash[:notice]).to eq("2 bookings marked as no-show.")
  end

  it "requires a reason before marking a no-show review booking" do
    booking = create(:booking, hotel: hotel, status: "review_no_show", no_show_review_business_date: Date.current)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 200.0)

    post mark_no_show_hotel_booking_path(hotel, booking), params: { no_show_reason: " " }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("No-show reason is required.")
    expect(booking.reload.status).to eq("review_no_show")
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
      params: { no_show_reason: "Guest did not arrive" },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_offcanvas"')
    expect(response.body).to include(CGI.escapeHTML(booking_details_path(booking)))
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
      params: { no_show_reason: "Guest did not arrive" },
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

    post mark_no_show_hotel_booking_path(hotel, booking), params: { no_show_reason: "Guest did not arrive" }

    expect(response).to redirect_to(booking_details_path(booking))
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

    expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "bookings", view: "list"))
    expect(flash[:alert]).to include("Please provide details for the backdated check-in reason")
    expect(booking.reload.status).to eq("review_no_show")
  end

  it "renders group reinstatement as a child-specific master-detail editor" do
    group = create(:group_booking, hotel: hotel)
    booking = create_group_child(group, status: "no_show", room_number: "101")
    create_group_child(group, status: "no_show", room_number: "102", guest_name: "Second Guest")

    get hotel_booking_transaction_reinstate_no_show_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Scheduled Stay", "Room Category", "Rate", "Room Number")
    expect(response.body).not_to include("Perform Reinstatement on:")
    expect(response.body).to include("reinstatements[")
    expect(response.body).to include("group-lifecycle-targets-master-detail-value=\"true\"")
    expect(response.body).to include("group-lifecycle-targets-selection-mode-value=\"radio\"")
    expect(response.body).to include('type="hidden" name="target_scope"')
    expect(response.body.scan('data-reinstatement-fields="true"').size).to eq(2)
    expect(response.body.scan('data-controller="booking-calc"').size).to be >= 2
    expect(response.body.scan('data-controller="room-lock"').size).to be >= 2

    document = Nokogiri::HTML(response.body)
    selected = document.at_css("input[name='booking_ids[]'][value='#{booking.id}']")
    booking_inputs = document.css("input[name='booking_ids[]']")
    active_panel = document.at_css("[data-group-lifecycle-targets-target='panel'][data-booking-id='#{booking.id}']")
    expect(booking_inputs.map { |input| input["type"] }.uniq).to eq([ "radio" ])
    expect(selected["checked"]).to eq("checked")
    expect(active_panel["hidden"]).to be_nil
    expect(active_panel["aria-hidden"]).to eq("false")
    expect(document.css("input[name='target_scope'][type='radio']")).to be_empty
  end

  it "uses the same canonical reinstatement fields for single bookings" do
    booking = create(:booking, hotel: hotel, status: "no_show")
    room = create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    get hotel_booking_transaction_reinstate_no_show_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Scheduled Stay", "Room Category", "Rate", "Room Number", "Reason for Reinstatement")
    expect(response.body).to include('data-reinstatement-fields="true"')
    expect(response.body).to include('data-controller="booking-calc"', 'data-controller="room-lock"')
    expect(response.body).to include("booking[booking_rooms_attributes][0][id]")
    expect(response.body).to include("value=\"#{room.id}\"")
    expect(response.body).not_to include("reinstatements[")
  end

  it "submits child-specific group reinstatement attributes to the batch service" do
    group = create(:group_booking, hotel: hotel)
    booking = create_group_child(group, status: "no_show", room_number: "101")
    room = booking.booking_rooms.first
    allow(Bookings::ReinstateGroup).to receive(:call).and_return(OpenStruct.new(success?: true, bookings: [ booking ]))

    post reinstate_hotel_booking_path(hotel, booking), params: {
      target_scope: "individual",
      booking_ids: [ booking.id ],
      retroactive_reason: "Guest arrived late",
      reinstatements: {
        booking.id.to_s => {
          booking_rooms_attributes: {
            "0" => { id: room.id, room_type_id: room.room_type_id, room_number: "101", rate_plan_id: "" }
          }
        }
      }
    }

    expect(response).to redirect_to(booking_details_path(booking))
    expect(Bookings::ReinstateGroup).to have_received(:call).with(
      group_booking: group,
      booking_attributes: hash_including(booking.id.to_s),
      user: user,
      options: hash_including(reason: "Guest arrived late")
    )
  end

  it "rejects group reinstatement when a selected child is not configured" do
    group = create(:group_booking, hotel: hotel)
    first = create_group_child(group, status: "no_show", room_number: "101")
    second = create_group_child(group, status: "no_show", room_number: "102")
    first_room = first.booking_rooms.first

    post reinstate_hotel_booking_path(hotel, first), params: {
      target_scope: "individual",
      booking_ids: [ first.id, second.id ],
      retroactive_reason: "Guest arrived late",
      reinstatements: {
        first.id.to_s => {
          booking_rooms_attributes: {
            "0" => { id: first_room.id, room_type_id: first_room.room_type_id, room_number: "101" }
          }
        }
      }
    }

    expect(response).to redirect_to(booking_details_path(first))
    expect(flash[:alert]).to include("Every selected booking must be configured")
    expect(first.reload.status).to eq("no_show")
    expect(second.reload.status).to eq("no_show")
  end
end
