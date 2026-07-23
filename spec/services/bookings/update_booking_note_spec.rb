# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateBookingNote do
  let(:booking) { create(:booking) }
  let(:actor) { create(:user, name: "Note Editor") }

  it "updates a note and appends its previous revision" do
    note = create(:booking_note, booking:, user: actor, body: "First note")

    result = described_class.call(note:, actor:, body: "  Updated note  ")

    expect(result).to be_success
    expect(note.reload.body).to eq("Updated note")
    expect(note.edit_history.last).to include("body" => "First note", "edited_by_name" => "Note Editor")
    expect(BookingAuditLog.where(auditable: booking, action_type: "note_updated")).to exist
  end

  it "rejects a blank update without changing history" do
    note = create(:booking_note, booking:, user: actor, body: "First note")

    result = described_class.call(note:, actor:, body: "  ")

    expect(result).not_to be_success
    expect(note.reload).to have_attributes(body: "First note", edit_history: [])
  end
end
