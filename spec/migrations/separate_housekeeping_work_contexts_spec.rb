# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260731120000_separate_housekeeping_work_contexts")

RSpec.describe SeparateHousekeepingWorkContexts do
  it "reads a turnover from the checkout its metadata names" do
    booking = create(:booking, status: "completed")
    checkout = create(:check_out_request, booking:, status: "in_progress")
    request = create(:housekeeping_request, booking:, request_details: "Old cleaning",
                     metadata: { "checkout_request_id" => checkout.id.to_s })

    described_class.new.send(:backfill_contexts)

    expect(request.reload.work_context).to eq("checkout_turnover")
  end

  # The details are the only thing rows this old say it with, which is the
  # string-reading the column exists to end. Read here once and never again.
  it "reads a turnover from the details, for rows written before the metadata" do
    booking = create(:booking, status: "completed")
    request = create(:housekeeping_request, booking:, room_number: "101",
                     request_details: "Checkout Room Cleaning")

    described_class.new.send(:backfill_contexts)

    expect(request.reload.work_context).to eq("checkout_turnover")
  end

  it "leaves the checkout requests alone" do
    booking = create(:booking, status: "completed")
    checkout = create(:check_out_request, booking:, status: "in_progress")

    expect { described_class.new.send(:backfill_contexts) }
      .not_to change { checkout.reload.attributes }
  end

  it "classifies remaining booking-backed and bookingless rows" do
    booking = create(:booking, status: "checked_in")
    occupied = create(:housekeeping_request, booking:, request_details: "Guest towels")
    vacant = create(:housekeeping_request, booking: nil, hotel: booking.hotel, request_details: "Deep clean")

    described_class.new.send(:backfill_contexts)

    expect(occupied.reload.work_context).to eq("guest_request")
    expect(vacant.reload.work_context).to eq("vacant_room_task")
  end
end
