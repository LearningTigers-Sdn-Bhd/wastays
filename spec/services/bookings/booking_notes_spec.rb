# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking note services" do
  let(:booking) { create(:booking) }
  let(:actor) { create(:user, name: "Note Editor") }

  it "creates a note with an audit entry" do
    result = Bookings::CreateBookingNote.call(booking:, actor:, body: "First note")

    expect(result).to be_success
    expect(result.note).to have_attributes(body: "First note", user: actor)
    expect(BookingAuditLog.where(auditable: booking, action_type: "note_added")).to exist
  end

  it "updates a note and appends its previous revision" do
    note = create(:booking_note, booking:, user: actor, body: "First note")

    result = Bookings::UpdateBookingNote.call(note:, actor:, body: "  Updated note  ")

    expect(result).to be_success
    expect(note.reload.body).to eq("Updated note")
    expect(note.edit_history.last).to include("body" => "First note", "edited_by_name" => "Note Editor")
    expect(BookingAuditLog.where(auditable: booking, action_type: "note_updated")).to exist
  end

  it "rejects a blank update without changing history" do
    note = create(:booking_note, booking:, user: actor, body: "First note")

    result = Bookings::UpdateBookingNote.call(note:, actor:, body: "  ")

    expect(result).not_to be_success
    expect(note.reload).to have_attributes(body: "First note", edit_history: [])
  end

  it "deletes a note while preserving an audit record" do
    note = create(:booking_note, booking:, user: actor, body: "Delete me")

    result = Bookings::DeleteBookingNote.call(note:, actor:)

    expect(result).to be_success
    expect(note).to be_destroyed
    audit = BookingAuditLog.find_by!(auditable: booking, action_type: "note_deleted")
    expect(audit.old_value).to eq("body" => "Delete me")
  end
end
