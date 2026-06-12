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
      guest: { name: "Added Guest", email: "added@example.com", phone: "123", country: "Malaysia", document_type: "ic" }
    }
    added = booking.reload.booking_guests.find_by!(is_primary: false)
    expect(added.guest.name).to eq("Added Guest")

    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_additional", booking_guest_id: added.id), params: {
      guest: { name: "Updated Guest", email: "updated@example.com", phone: "456", country: "Singapore", document_type: "passport" }
    }
    expect(added.guest.reload).to have_attributes(name: "Updated Guest", country: "Singapore")
  end

  it "edits the primary guest through booking synchronization" do
    patch hotel_booking_show_action_manage_guest_path(hotel, booking, mode: "edit_primary"), params: {
      guest: {
        name: "Updated Primary", email: "primary@example.com", phone: "123456",
        country: "Malaysia", document_type: "passport", government_id: "P123"
      }
    }

    expect(booking.reload).to have_attributes(guest_name: "Updated Primary", guest_email: "primary@example.com")
    expect(booking.primary_guest).to have_attributes(name: "Updated Primary", document_type: "passport", government_id: "p123")
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

    get hotel_booking_path(hotel, booking)

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
    expect(response.body).to include(hotel_booking_path(hotel, booking))
  end
end
