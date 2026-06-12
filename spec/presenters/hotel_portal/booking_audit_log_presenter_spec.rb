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

  it "safely presents unknown future actions" do
    presenter = presenter_for(action_type: "future_event", category: "other")

    expect(presenter.title).to eq("Future event")
    expect(presenter.summary).to include("recorded future event")
  end
end
