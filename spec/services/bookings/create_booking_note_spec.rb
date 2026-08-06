# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreateBookingNote do
  let(:booking) { create(:booking) }
  let(:actor) { create(:user, name: "Note Editor") }

  it "creates a note with an audit entry" do
    result = described_class.call(booking:, actor:, body: "First note")

    expect(result).to be_success
    expect(result.note).to have_attributes(body: "First note", user: actor)
    expect(BookingAuditLog.where(auditable: booking, action_type: "note_added")).to exist
  end
end
