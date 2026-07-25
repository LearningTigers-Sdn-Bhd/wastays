# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::GroupBatchResult do
  it "reports the moved transactions and the bookings it touched" do
    result = described_class.success(transactions: [ "moved" ], touched_booking_ids: [ 7 ])

    expect(result).to be_success
    expect(result.transactions).to eq([ "moved" ])
    expect(result.touched_booking_ids).to eq([ 7 ])
  end

  it "reports nothing touched on failure" do
    result = described_class.failure("Booking No. 12: rule invalid", transactions: [], touched_booking_ids: [])

    expect(result).not_to be_success
    expect(result.touched_booking_ids).to eq([])
  end
end
