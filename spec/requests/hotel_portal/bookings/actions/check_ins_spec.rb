# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions check-ins", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved", tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: %w[101 102 103]) }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      status: "confirmed",
      guest_name: "Ada Lovelace",
      guest_country: "United States",
      check_in: Time.zone.now,
      check_out: 2.days.from_now,
      tourism_tax_applied: true,
      tourism_tax_amount: 20.0,
      tax_posting_snapshot: {
        Date.current.iso8601 => [ { "name" => "Tourism Tax", "type" => "tourism_tax", "amount" => "20.00" } ]
      },
      booking_quote: nil
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
    end
  end

  def grant_permission(slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def valid_params(record = booking, room_number: "101")
    {
      check_in: {
        checked_in_at: Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M"),
        tourism_tax_collected: "0",
        room_assignments: {
          record.booking_rooms.first.id.to_s => { room_number: room_number }
        }
      }
    }
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission("manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the check-in form" do
    it "renders the standard check-in Sheet in the requesting frame" do
      get hotel_booking_action_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-check-in-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Check in guest", "Arrival details", "Room assignments", "Security deposit", "Tourism tax")
      expect(dialog.at_css("input[name='check_in[checked_in_at]']")).to be_present
      expect(dialog.at_css("select[name='check_in[room_assignments][#{booking.booking_rooms.first.id}][room_number]']")).to be_present
      expect(response.body).not_to include("offcanvas")
    end

    it "offers the property's boat timetable, and hides the section when boats are off" do
      hotel.update!(allow_boat_information: true)
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "08:00")
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "15:30")

      get hotel_booking_action_check_in_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }

      options = Nokogiri::HTML(response.body).css("select[name='check_in[boat_in_time]'] option").map { |option| option["value"] }
      expect(options).to eq([ "", "08:00" ])

      hotel.update!(allow_boat_information: false)
      get hotel_booking_action_check_in_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response.body).not_to include("check_in[boat_in_time]")
    end

    it "renders edit mode in the secondary frame" do
      booking.update_columns(status: "checked_in", checked_in_at: 1.hour.ago)

      get hotel_booking_action_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-check-in-sheet")
      expect(dialog.text).to include("Edit check-in details", "Reason to change")
      expect(dialog.text).not_to include("Security deposit", "Tourism tax")
    end

    it "renders the group selector beside one static complete check-in form" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      get hotel_booking_action_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      expect(response.body).to include("Perform Check-in on:", "Ada Lovelace", "Grace Hopper")
      expect(document.css("[data-group-lifecycle-targets-target='panel']")).to be_empty

      # Each selectable row needs a unique id so its label targets its own control
      # (a shared id makes every label toggle the first checkbox).
      target_ids = document.css("input[name='booking_ids[]']").map { |input| input["id"] }
      expect(target_ids).to all(be_present)
      expect(target_ids.uniq).to eq(target_ids)
      expect(document.css("label[for^='group-target-']").map { |label| label["for"] }).to match_array(target_ids)
      expect(document.at_css("select[name='check_in[room_assignments][#{booking.booking_rooms.first.id}][room_number]']")).to be_present
      expect(document.css("select[name*='[room_assignments]']").size).to eq(1)
      expect(response.body).to include("Record a security deposit", "Tourism tax collected")
    end
  end

  describe "POST the check-in" do
    it "checks in a guest and completes the requesting Sheet" do
      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params,
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"')
      expect(booking.reload.status).to eq("checked_in")
      expect(flash[:notice]).to eq("Guest checked in successfully.")
    end

    it "records the boat slots picked at check-in against the stay dates" do
      hotel.update!(allow_boat_information: true)
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "08:00")
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "15:30")
      guest = create(:booking_guest, booking: booking, guest: create(:guest), is_primary: true)

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params.deep_merge(check_in: { boat_in_time: "08:00", boat_out_time: "15:30" }),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      guest.reload
      zone = hotel.hotel_time_zone
      expect(guest.boat_in_at.in_time_zone(zone).strftime("%Y-%m-%d %H:%M"))
        .to eq("#{booking.check_in.in_time_zone(zone).strftime('%Y-%m-%d')} 08:00")
      expect(guest.boat_out_at.in_time_zone(zone).strftime("%Y-%m-%d %H:%M"))
        .to eq("#{booking.check_out.in_time_zone(zone).strftime('%Y-%m-%d')} 15:30")
    end

    it "ignores forged boat slots when the hotel disables boat information" do
      hotel.update!(allow_boat_information: false)
      guest = create(:booking_guest, booking: booking, guest: create(:guest), is_primary: true)

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params.deep_merge(check_in: { boat_in_time: "08:00" }),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(booking.reload.status).to eq("checked_in")
      expect(guest.reload.boat_in_at).to be_nil
    end

    it "completes a committed check-in and releases its room lock when notification dispatch fails" do
      create(:room_lock, hotel: hotel, room_type: room_type, room_number: "101", user: user, expires_at: 10.minutes.from_now)
      allow(Notifications::Dispatcher).to receive(:new).and_raise("notification outage")

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params,
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(booking.reload.status).to eq("checked_in")
      expect(RoomLock.where(hotel: hotel, room_type: room_type, room_number: "101", user: user)).not_to exist
    end

    it "updates check-in time with a reason and completes a stacked Sheet" do
      booking.update_columns(status: "checked_in", checked_in_at: 1.day.ago)
      new_time = Time.current.in_time_zone(hotel.hotel_time_zone).change(min: 0).strftime("%Y-%m-%dT%H:%M")

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params.deep_merge(check_in: { checked_in_at: new_time, reason: "Correcting arrival record" }),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response.body).to include('target="booking_action_sheet_secondary"')
      expect(booking.reload.checked_in_at.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")).to eq(new_time)
      expect(BookingAuditLog.where(auditable: booking, action_type: "edit_check_in").last.metadata["reason"]).to eq("Correcting arrival record")
      expect(flash[:notice]).to eq("Check-in details updated.")
    end

    it "keeps edit mode open and preserves values when the reason is missing" do
      booking.update_columns(status: "checked_in", checked_in_at: 1.day.ago)
      submitted_time = 2.hours.ago.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params.deep_merge(check_in: { checked_in_at: submitted_time, reason: "" }),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Reason to change is required.", submitted_time, "dialog")
      expect(response.body).not_to include('action="complete_sheet"')
    end

    it "updates the secondary frame when stacked validation fails" do
      booking.update_columns(status: "checked_in", checked_in_at: 1.day.ago)

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params.deep_merge(check_in: { reason: "" }),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="booking_action_sheet_secondary"', "Reason to change is required.")
      expect(response.body).not_to include('target="booking_action_sheet"')
    end

    it "returns a form error instead of raising for malformed nested parameters" do
      post hotel_booking_action_check_in_path(hotel, booking),
        params: { check_in: "invalid" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Check-in date and time is required.")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "parses the submitted time in the hotel time zone" do
      user.update!(time_zone: "Eastern Time (US & Canada)")
      local_time = "#{Date.current.iso8601}T18:30"

      post hotel_booking_action_check_in_path(hotel, booking), params: valid_params.deep_merge(check_in: { checked_in_at: local_time })

      expect(booking.reload.checked_in_at).to eq(hotel.hotel_time_zone.parse(local_time))
    end

    it "rejects a room number outside the booking room type" do
      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params(room_number: "999"),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Room 999 does not belong")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "rejects a room locked by another staff member" do
      other_user = create(:user, account: hotel.account)
      create(:room_lock, hotel: hotel, room_type: room_type, room_number: "102", user: other_user, expires_at: 10.minutes.from_now)

      post hotel_booking_action_check_in_path(hotel, booking),
        params: valid_params(room_number: "102"),
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Room 102 is no longer available")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "ignores forged general booking attributes" do
      original_total = booking.total_amount

      post hotel_booking_action_check_in_path(hotel, booking), params: valid_params.deep_merge(
        check_in: { total_amount: "1.00", guest_name: "Forged Name", room_type_id: create(:room_type, hotel: other_hotel).id }
      )

      booking.reload
      expect(booking.status).to eq("checked_in")
      expect(booking.total_amount).to eq(original_total)
      expect(booking.guest_name).to eq("Ada Lovelace")
      expect(booking.booking_rooms.first.room_type).to eq(room_type)
    end

    it "records a security deposit with an allowlisted method" do
      params = valid_params.deep_merge(check_in: {
        collect_security_deposit: "1",
        security_deposit: { amount: "75.00", payment_method: "credit_card", external_reference: "AUTH-1" }
      })

      expect { post hotel_booking_action_check_in_path(hotel, booking), params: params }.to change(Deposit, :count).by(1)

      deposit = Deposit.last
      expect(deposit).to have_attributes(amount: 75.to_d, payment_method: "credit_card", external_reference: "AUTH-1")
    end

    it "rejects an unknown security deposit method" do
      params = valid_params.deep_merge(check_in: {
        collect_security_deposit: "1",
        security_deposit: { amount: "75.00", payment_method: "crypto" }
      })

      post hotel_booking_action_check_in_path(hotel, booking),
        params: params,
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Select a valid security deposit payment method.")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "posts the canonical tourism-tax amount once" do
      grant_permission("post_folio_payments")
      params = valid_params.deep_merge(check_in: { tourism_tax_collected: "1", tourism_tax_amount: "999.00" })

      expect { post hotel_booking_action_check_in_path(hotel, booking), params: params }.to change(FolioTransaction.payment, :count).by(1)
      payment = booking.reload.booking_folio.folio_transactions.payment.sole
      expect(payment.amount).to eq(20.to_d)
      expect(payment.metadata["source"]).to eq("tourism_tax_check_in")
    end

    it "checks in selected group children atomically from the shared static form" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", guest_name: "Grace Hopper", check_in: booking.check_in, check_out: booking.check_out)
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      timestamp = Time.current.strftime("%Y-%m-%dT%H:%M")
      post hotel_booking_action_check_in_path(hotel, booking), params: {
        target_scope: "group",
        booking_ids: [ booking.id, sibling.id ],
        check_in: {
          checked_in_at: timestamp,
          room_assignments: { booking.booking_rooms.first.id.to_s => { room_number: "101" } },
          collect_security_deposit: "1",
          security_deposit: { amount: "40.00", payment_method: "cash", external_reference: "GROUP" }
        }
      }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(booking.reload.status).to eq("checked_in")
      expect(sibling.reload.status).to eq("checked_in")
      expect(booking.deposits.reload.pluck(:amount)).to contain_exactly(40.to_d)
      expect(sibling.deposits.reload.pluck(:amount)).to contain_exactly(40.to_d)
      expect(flash[:notice]).to eq("2 bookings checked in.")
    end

    it "rolls back the group when a selected child has no assigned room" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", check_in: booking.check_in, check_out: booking.check_out)
      create(:booking_room, booking: sibling, room_type: room_type, room_number: nil)

      post hotel_booking_action_check_in_path(hotel, booking),
        params: {
          target_scope: "group",
          booking_ids: [ booking.id, sibling.id ],
          check_in: {
            checked_in_at: Time.current.strftime("%Y-%m-%dT%H:%M"),
            room_assignments: { booking.booking_rooms.first.id.to_s => { room_number: "101" } }
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Assign every room before checking in.")
      expect(booking.reload.status).to eq("confirmed")
      expect(sibling.reload.status).to eq("confirmed")
    end

    it "checks in selected siblings without requiring an excluded unassigned anchor" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.booking_rooms.first.update!(room_number: nil)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", guest_name: "Grace Hopper", check_in: booking.check_in, check_out: booking.check_out)
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")

      post hotel_booking_action_check_in_path(hotel, booking), params: {
        target_scope: "individual",
        booking_ids: [ sibling.id ],
        check_in: { checked_in_at: Time.current.strftime("%Y-%m-%dT%H:%M") }
      }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(booking.reload.status).to eq("confirmed")
      expect(sibling.reload.status).to eq("checked_in")
    end

    it "updates the booking snapshot after changing the anchor room" do
      post hotel_booking_action_check_in_path(hotel, booking), params: valid_params(room_number: "102")

      booking.reload
      expect(booking.booking_rooms.first.room_number).to eq("102")
      expect(booking.hotel_snapshot["room_number"] || booking.hotel_snapshot.dig("assignment", "room_number")).to eq("102")
    end

    it "honors a valid return path for a direct HTML submission" do
      destination = hotel_front_desk_path(hotel, tab: "arrivals")

      post hotel_booking_action_check_in_path(hotel, booking), params: valid_params.merge(return_to: destination)

      expect(response).to redirect_to(destination)
      expect(response).to have_http_status(:see_other)
    end

    it "blocks users without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_check_in_path(hotel, booking), params: valid_params

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("confirmed")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "confirmed")

      post hotel_booking_action_check_in_path(hotel, other_booking), params: { check_in: { checked_in_at: Time.current } }

      expect(response).to have_http_status(:not_found)
    end
  end
end
