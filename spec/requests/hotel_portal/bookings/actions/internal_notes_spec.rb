# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions internal notes", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel:, guest_name: "Ada Lovelace") }

  before do
    %w[manage_bookings view_bookings].each do |slug|
      permission = Permission.find_by(slug:) || create(:permission, slug:, name: slug.tr("_", " ").titleize)
      create(:role_permission, role:, permission:)
    end
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders the add form in the booking action Sheet" do
    get hotel_booking_action_internal_notes_path(hotel, booking, mode: "add"),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("turbo-frame#booking_action_sheet dialog#booking-internal-note-sheet")).to be_present
    expect(document.at_css("textarea[name='booking_note[body]'][required]")).to be_present
    expect(response.body).not_to include("offcanvas")
  end

  it "adds a note and completes the requesting Sheet" do
    post hotel_booking_action_internal_notes_path(hotel, booking, mode: "add"),
      params: { booking_note: { body: "First note" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"')
    expect(booking.booking_notes.last).to have_attributes(body: "First note", user: user)
  end

  it "keeps the Sheet open on validation failure" do
    post hotel_booking_action_internal_notes_path(hotel, booking, mode: "add"),
      params: { booking_note: { body: "" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("booking-internal-note-sheet", "Body can&#39;t be blank")
  end

  it "edits a note and displays its history" do
    note = create(:booking_note, booking:, user:, body: "First note")

    patch hotel_booking_action_internal_notes_path(hotel, booking, mode: "edit", note_id: note.id),
      params: { booking_note: { body: "Updated note" } }
    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
    expect(note.reload.body).to eq("Updated note")

    get hotel_booking_action_internal_notes_path(hotel, booking, mode: "history", note_id: note.id),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-internal-note-history-sheet")).to be_present
    expect(document.at_css("dialog").text).to include("First note")
  end

  it "renders and completes note deletion" do
    note = create(:booking_note, booking:, user:, body: "Delete me", edit_history: [ { "body" => "Older" } ])

    get hotel_booking_action_delete_internal_note_path(hotel, booking, note),
      headers: { "Turbo-Frame" => "booking_action_sheet" }
    expect(Nokogiri::HTML(response.body).at_css("dialog#booking-internal-note-deletion-sheet")).to be_present

    delete hotel_booking_action_delete_internal_note_path(hotel, booking, note),
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }
    expect(response.body).to include('action="complete_sheet"')
    expect(booking.booking_notes.where(id: note.id)).not_to exist
  end

  it "renders notes and Sheet launchers in Booking Details" do
    note = create(:booking_note, booking:, user:, body: "Operational note")

    get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#internal-notes-heading").text).to eq("Internal notes")
    expect(document.text).to include("Operational note")
    links = document.css("a[data-turbo-frame='booking_action_sheet']")
    expect(links.map { |link| link["href"] }).to include(
      hotel_booking_action_internal_notes_path(hotel, booking, mode: "add", return_to: hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")),
      hotel_booking_action_internal_notes_path(hotel, booking, mode: "edit", note_id: note.id, return_to: hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
    )
  end

  it "requires manage-bookings permission for every note action" do
    role.role_permissions.destroy_all

    get hotel_booking_action_internal_notes_path(hotel, booking, mode: "add")

    expect(response).to redirect_to(root_path)
  end

  it "shows note content but hides management launchers from read-only users" do
    create(:booking_note, booking:, user:, body: "Read-only operational note")
    role.role_permissions.find_by!(permission: Permission.find_by!(slug: "manage_bookings")).destroy!

    get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Read-only operational note")
    expect(response.body).not_to include(hotel_booking_action_internal_notes_path(hotel, booking))
  end

  it "rejects unsupported modes and notes from another booking" do
    other_note = create(:booking_note)

    get hotel_booking_action_internal_notes_path(hotel, booking, mode: "unsupported")
    expect(response).to have_http_status(:not_found)

    get hotel_booking_action_internal_notes_path(hotel, booking, mode: "history", note_id: other_note.id)
    expect(response).to have_http_status(:not_found)
  end
end
