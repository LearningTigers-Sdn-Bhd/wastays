# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ReservationRow do
  it "reads a row that sets none of the layout-specific fields as a plain Reservation List row" do
    row = described_class.new(reservation_number: "412301", guest_name: "A GUEST")

    expect(row).not_to be_cancelled
    expect(row).not_to be_explicit_layout
    expect(row.layout).to be_nil
    expect(row.boat_in).to be_nil
  end

  it "knows when a layout resolved the fields itself" do
    expect(described_class.new(layout: :reservation_csv)).to be_explicit_layout
    expect(described_class.new(layout: :reservation_list)).not_to be_explicit_layout
  end

  it "is cancelled only when its booking status says so" do
    expect(described_class.new(booking_status: "cancelled")).to be_cancelled
    expect(described_class.new(booking_status: "pending")).not_to be_cancelled
    expect(described_class.new(booking_status: nil)).not_to be_cancelled
  end
end
