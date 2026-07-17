# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingAuditLogPresenter do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "John Doe", currency: "MYR") }
  let(:user) { create(:user, name: "Sarah") }

  def presenter_for(**attributes)
    log = build(
      :booking_audit_log,
      { hotel: hotel, auditable: booking, user: user, occurred_at: Time.utc(2026, 6, 12, 7, 30) }.merge(attributes)
    )
    described_class.new(log, hotel: hotel)
  end

  it "describes status changes in operational language" do
    presenter = presenter_for(
      action_type: "status_change",
      category: "status",
      old_value: { "status" => "checked_in" },
      new_value: { "status" => "review_due_out" },
      metadata: { "from" => "checked_in", "to" => "review_due_out" }
    )

    expect(presenter.title).to eq("Booking moved to Pending late-checkout review")
    expect(presenter.summary).to eq("Booking moved from Checked in to Pending late-checkout review.")
  end

  it "shows actor, reason, room, and hotel-local time for check-in" do
    presenter = presenter_for(
      action_type: "check_in",
      category: "status",
      metadata: { "room_number" => "101", "reason" => "Internet outage" }
    )

    expect(presenter.summary).to eq("Sarah checked John Doe in to Room 101.")
    expect(presenter.context_details).to include([ "Reason", "Internet outage" ])
    expect(presenter.occurred_at_label).to eq("12 Jun 2026, 03:30 PM")
  end

  it "hides technical fields and formats friendly changes" do
    presenter = presenter_for(
      action_type: "update",
      category: "stay",
      old_value: { "status" => "confirmed", "hotel_snapshot" => { "id" => 1 }, "total_amount" => "100" },
      new_value: { "status" => "checked_in", "hotel_snapshot" => { "id" => 2 }, "total_amount" => "120" }
    )

    expect(presenter.formatted_changes.map { |change| change[:field] }).to contain_exactly("Booking status", "Booking total")
    expect(presenter.formatted_changes.last[:new]).to include("MYR")
  end

  it "redacts sensitive audit values" do
    presenter = presenter_for(
      action_type: "update",
      category: "stay",
      old_value: {
        "guest_email" => "old@example.com",
        "guest_phone" => "+60111111111",
        "government_id" => "A1234567",
        "date_of_birth" => "1990-01-01",
        "guest_government_id" => "C1111111",
        "guest_date_of_birth" => "1992-03-03",
        "guest_home_address" => "Private old address",
        "access_token" => "old-secret-token",
        "encryption_key" => "old-encryption-key",
        "body" => "Private staff note"
      },
      new_value: {
        "guest_email" => "new@example.com",
        "guest_phone" => "+60222222222",
        "government_id" => "B7654321",
        "date_of_birth" => "1991-02-02",
        "guest_government_id" => "D2222222",
        "guest_date_of_birth" => "1993-04-04",
        "guest_home_address" => "Private new address",
        "access_token" => "new-secret-token",
        "encryption_key" => "new-encryption-key",
        "body" => "Updated private note"
      }
    )

    changes = presenter.formatted_changes
    expect(changes.map { |change| change[:field] }).to contain_exactly(
      "Guest email", "Guest phone", "Date of birth", "Guest date of birth", "Guest home address", "Access token", "Encryption key", "Note"
    )
    expect(changes.flat_map { |change| change.values_at(:old, :new) }.uniq).to eq([ "Redacted" ])
    expect(changes.to_s).not_to include("A1234567", "B7654321", "C1111111", "D2222222", "Private old address", "Private new address", "old-secret-token", "new-secret-token", "old-encryption-key", "new-encryption-key")
  end

  it "safely presents unknown future actions" do
    presenter = presenter_for(action_type: "future_event", category: "other")

    expect(presenter.title).to eq("Future event")
    expect(presenter.summary).to include("recorded future event")
  end
end
