# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::SetPrimaryGuest do
  it "promotes the selected guest and demotes the previous primary" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    previous = create(:booking_guest, booking: booking, is_primary: true)
    selected = create(:booking_guest, booking: booking, is_primary: false)

    expect {
      @result = described_class.call(booking: booking, booking_guest: selected, actor: actor)
    }.to change { BookingAuditLog.where(auditable: booking, action_type: "update").count }.by(1)
    result = @result
    audit_log = BookingAuditLog.where(auditable: booking, action_type: "update").order(:id).last

    expect(result).to be_success
    expect(result.booking_guest).to eq(selected)
    expect(previous.reload).to have_attributes(role: "additional", is_primary: false)
    expect(selected.reload).to have_attributes(role: "primary", is_primary: true)
    expect(audit_log).to have_attributes(
      auditable: booking,
      user: actor,
      action_type: "update",
      category: "other",
      source: "booking_control_panel"
    )
    expect(audit_log.old_value).to eq("primary_booking_guest_id" => previous.id)
    expect(audit_log.new_value).to eq("primary_booking_guest_id" => selected.id)
  end

  it "rejects a guest from another booking" do
    booking = create(:booking)
    outsider = create(:booking_guest, booking: create(:booking, hotel: booking.hotel), is_primary: true)

    result = described_class.call(booking: booking, booking_guest: outsider)

    expect(result).not_to be_success
    expect(result.error).to eq("Guest must belong to the selected booking.")
    expect(result.booking_guest).to be_nil
  end
end
