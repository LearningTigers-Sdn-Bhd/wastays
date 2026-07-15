# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal booking show actions", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, guest_country: "Malaysia") }

  before do
    permission = Permission.find_by(slug: "manage_bookings") || create(:permission, slug: "manage_bookings", name: "Manage Bookings")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "tourism tax voucher print menu entry" do
    it "shows an active link whenever booking owes tourism tax" do
      booking.update!(guest_country: "Singapore", tourism_tax_amount: 20.0, tourism_tax_applied: true, tax_lines: [ { "type" => "tourism_tax", "amount" => 20.0 } ])

      get hotel_booking_transaction_show_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Issue Tourism Tax Voucher")
      expect(response.body).to include(issue_hotel_booking_tourism_tax_voucher_path(hotel, booking))
    end

    it "omits entry when booking has no tourism tax" do
      get hotel_booking_transaction_show_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Tourism Tax Voucher")
    end
  end

  it "renders guest add and edit sheets in the offcanvas frame" do
    additional = create(:booking_guest, booking: booking, is_primary: false)

    [
      hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "add"),
      hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_primary"),
      hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_additional", booking_guest_id: additional.id)
    ].each do |path|
      get path, headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
    end
  end

  it "adds and edits additional guests" do
    post hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "add"), params: {
      guest: { name: "Added Guest", email: "added@example.com", phone: "123", country: "Malaysia", document_type: "passport", date_of_birth: "1993-04-05" }
    }
    added = booking.reload.booking_guests.find_by!(is_primary: false)
    expect(added.guest.name).to eq("Added Guest")
    expect(added.guest.date_of_birth).to eq(Date.new(1993, 4, 5))

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_additional", booking_guest_id: added.id), params: {
      guest: { name: "Updated Guest", email: "updated@example.com", phone: "456", country: "Singapore", document_type: "passport", date_of_birth: "1994-06-07" }
    }
    expect(added.guest.reload).to have_attributes(name: "Updated Guest", country: "Singapore", date_of_birth: Date.new(1994, 6, 7))
  end

  it "edits the primary guest through booking synchronization" do
    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_primary"), params: {
      guest: {
        name: "Updated Primary", email: "primary@example.com", phone: "123456",
        country: "Malaysia", document_type: "passport", government_id: "P123", date_of_birth: "1990-01-02"
      }
    }

    expect(booking.reload).to have_attributes(guest_name: "Updated Primary", guest_email: "primary@example.com")
    expect(booking.primary_guest).to have_attributes(
      name: "Updated Primary",
      document_type: "passport",
      government_id: "p123",
      date_of_birth: Date.new(1990, 1, 2)
    )
  end

  it "returns inline guest updates to the booking control panel" do
    primary = create(:booking_guest, booking: booking, is_primary: true)
    return_to = hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: primary.id)

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_primary"), params: {
      presentation: "booking_control_panel",
      return_to: return_to,
      guest: {
        name: "Inline Primary", email: "inline@example.com", phone: "123456",
        country: "Malaysia", document_type: "ic", government_id: "900101011234", date_of_birth: "1990-01-01"
      }
    }

    expect(response).to redirect_to(return_to)
    expect(flash[:notice]).to eq("Guest details saved.")
    expect(booking.reload.guest_name).to eq("Inline Primary")
    expect(primary.reload).to have_attributes(name_snapshot: "Inline Primary", date_of_birth_snapshot: Date.new(1990, 1, 1))
    expect(primary.guest.reload.name).not_to eq("Inline Primary")
  end

  it "updates both snapshot and reusable guest record when explicitly requested" do
    additional = create(:booking_guest, booking: booking, is_primary: false)
    original_guest = additional.guest

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_additional", booking_guest_id: additional.id), params: {
      presentation: "booking_control_panel",
      save_scope: "snapshot_and_profile",
      return_to: hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: additional.id),
      guest: {
        name: "Shared Update", email: "shared@example.com", phone: "789",
        country: "Malaysia", document_type: "ic", government_id: "900101011234", date_of_birth: "1990-01-01"
      }
    }

    expect(flash[:notice]).to eq("Guest details and guest record updated.")
    expect(additional.reload.name_snapshot).to eq("Shared Update")
    expect(original_guest.reload.name).to eq("Shared Update")
  end

  it "returns inline validation errors without rendering an offcanvas fragment" do
    additional = create(:booking_guest, booking: booking, is_primary: false)
    return_to = hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: additional.id)

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_additional", booking_guest_id: additional.id), params: {
      presentation: "booking_control_panel",
      return_to: return_to,
      guest: { name: "", country: "Malaysia" }
    }

    expect(response).to redirect_to(return_to)
    expect(flash[:alert]).to include("Name can't be blank")
  end

  it "edits a passport primary guest when the booking has no linked primary guest yet" do
    booking.booking_guests.destroy_all

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_primary"), params: {
      guest: {
        name: "Aisyah Rahman",
        email: "ws-ttx-002@example.com",
        phone: "+601700002002",
        country: "Afghanistan",
        gender: "female",
        document_type: "passport",
        government_id: "785764675878",
        date_of_birth: "2000-06-15"
      }
    }

    expect(response).to have_http_status(:redirect)
    expect(booking.reload).to have_attributes(
      guest_country: "Afghanistan",
      guest_document_type: "passport"
    )
    expect(booking.primary_guest).to have_attributes(
      name: "Aisyah Rahman",
      country: "Afghanistan",
      gender: "female",
      document_type: "passport",
      government_id: "785764675878",
      date_of_birth: Date.new(2000, 6, 15)
    )
  end

  it "renders validation failures inside the guest sheet" do
    post hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "add"),
      params: { guest: { name: "", country: "Malaysia" } },
      headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Guest could not be saved")
  end

  it "confirms and removes only additional guests" do
    additional = create(:booking_guest, booking: booking, is_primary: false)
    primary = create(:booking_guest, booking: booking, is_primary: true)

    get hotel_booking_show_action_confirmation_path(hotel, booking, action_type: "remove_guest", target_id: additional.id),
      headers: { "Turbo-Frame" => "offcanvas_drawer" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Remove Guest")

    delete hotel_booking_show_action_confirmation_path(hotel, booking, action_type: "remove_guest", target_id: additional.id)
    expect(booking.booking_guests.where(id: additional.id)).not_to exist

    get hotel_booking_show_action_confirmation_path(hotel, booking, action_type: "remove_guest", target_id: primary.id)
    expect(response).to have_http_status(:not_found)
  end

  it "adds, edits, displays history, and confirms deletion of internal notes" do
    post hotel_booking_show_action_manage_internal_notes_path(hotel, booking, mode: "add"), params: {
      booking_note: { body: "First note" }
    }
    note = booking.booking_notes.last
    expect(note.body).to eq("First note")

    patch hotel_booking_show_action_manage_internal_notes_path(hotel, booking, mode: "edit", note_id: note.id), params: {
      booking_note: { body: "Updated note" }
    }
    expect(note.reload.body).to eq("Updated note")
    expect(note.edit_history).to be_present

    get hotel_booking_show_action_manage_internal_notes_path(hotel, booking, mode: "history", note_id: note.id),
      headers: { "Turbo-Frame" => "offcanvas_drawer" }
    expect(response.body).to include("First note")

    delete hotel_booking_show_action_confirmation_path(hotel, booking, action_type: "delete_internal_note", target_id: note.id)
    expect(booking.booking_notes.where(id: note.id)).not_to exist
    expect(BookingAuditLog.where(auditable: booking, action_type: "note_deleted")).to exist
  end

  it "rejects unsupported actions and cross-hotel records" do
    other_booking = create(:booking)

    get hotel_booking_show_action_confirmation_path(hotel, booking, action_type: "unsupported", target_id: "1")
    expect(response).to have_http_status(:not_found)

    get hotel_booking_show_action_manage_guest_path(hotel, other_booking, mode: "add")
    expect(response).to have_http_status(:not_found)

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "add"), params: {
      guest: { name: "Invalid mode", country: "Malaysia" }
    }
    expect(response).to have_http_status(:not_found)
  end

  it "hides management launchers from read-only users" do
    role.permissions.delete(Permission.find_by!(slug: "manage_bookings"))
    view_permission = Permission.find_by(slug: "view_bookings") || create(:permission, slug: "view_bookings", name: "View Bookings")
    create(:role_permission, role: role, permission: view_permission)

    get hotel_booking_control_panel_path(hotel, booking)

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include(hotel_booking_show_action_manage_guest_path(hotel, booking))
    expect(response.body).not_to include(hotel_booking_show_action_manage_internal_notes_path(hotel, booking))
  end

  it "blocks show action endpoints without manage-bookings permission" do
    role.permissions.delete(Permission.find_by!(slug: "manage_bookings"))

    get hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "add")

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
  end

  it "completes successful Turbo submissions back to the booking page" do
    post hotel_booking_show_action_manage_internal_notes_path(hotel, booking, mode: "add"),
      params: { booking_note: { body: "Turbo note" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("complete_offcanvas")
    expect(response.body).to include(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
  end
end
