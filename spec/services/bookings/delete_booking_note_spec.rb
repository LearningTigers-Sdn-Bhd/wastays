# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::DeleteBookingNote do
  let(:booking) { create(:booking) }
  let(:actor) { create(:user, name: "Note Editor") }

  it "deletes a note while preserving an audit record" do
    note = create(:booking_note, booking:, user: actor, body: "Delete me")

    result = described_class.call(note:, actor:)

    expect(result).to be_success
    expect(note).to be_destroyed
    audit = BookingAuditLog.find_by!(auditable: booking, action_type: "note_deleted")
    expect(audit.old_value).to eq("body" => "Delete me")
  end
end
