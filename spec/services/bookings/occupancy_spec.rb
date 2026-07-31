# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::Occupancy do
  it "treats the occupied booking states as occupied" do
    %w[checked_in review_due_out checkout_required].each do |status|
      booking = build(:booking, status:)

      expect(described_class.occupied?(booking)).to be(true), "expected #{status} to be occupied"
    end
  end

  it "treats pre-arrival and completed states as non-occupied" do
    %w[pending confirmed review_no_show completed cancelled].each do |status|
      booking = build(:booking, status:)

      expect(described_class.occupied?(booking)).to be(false), "expected #{status} to be non-occupied"
    end
  end

  it "handles a missing booking" do
    expect(described_class.occupied?(nil)).to be(false)
  end

  it "accepts guest requests from arrival onwards and before it" do
    %w[confirmed review_no_show checked_in review_due_out checkout_required].each do |status|
      booking = build(:booking, status:)

      expect(described_class.accepts_guest_requests?(booking)).to be(true), "expected #{status} to accept requests"
    end
  end

  it "refuses guest requests for a stay that has not been made or is over" do
    %w[pending completed cancelled no_show voided].each do |status|
      booking = build(:booking, status:)

      expect(described_class.accepts_guest_requests?(booking)).to be(false), "expected #{status} to refuse requests"
    end

    expect(described_class.accepts_guest_requests?(nil)).to be(false)
  end
end
