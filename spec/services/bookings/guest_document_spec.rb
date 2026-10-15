require "rails_helper"

RSpec.describe Bookings::GuestDocument do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel) }

  def call(kind, subject: booking, submission: nil)
    described_class.new(booking: subject, kind: kind, submission: submission).call
  end

  it "names every kind it can build" do
    expect(described_class::KINDS).to eq(%i[receipt invoice summary voucher_pack e_invoice])
  end

  it "refuses a kind it does not know" do
    expect { call(:passport) }.to raise_error(ArgumentError, /passport/)
  end

  it "builds the receipt with the confirmation code in the filename" do
    result = call(:receipt)

    expect(result.success?).to be true
    expect(result.bytes).to start_with("%PDF")
    expect(result.filename).to eq("wastays-receipt-#{booking.confirmation_token}.pdf")
  end

  it "turns a missing closed folio into a plain message" do
    result = call(:invoice)

    expect(result.success?).to be false
    expect(result.error).to eq("No finalized guest invoice is available for this booking.")
  end

  it "refuses a voucher pack for a booking with no group" do
    result = call(:voucher_pack)

    expect(result.success?).to be false
    expect(result.error).to eq("This booking is not part of a group.")
  end

  it "refuses an e-invoice with no submission" do
    result = call(:e_invoice)

    expect(result.success?).to be false
    expect(result.error).to include("No e-invoice is available")
  end

  it "names the group in the summary filename when the booking is in a group" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group)

    result = call(:summary, subject: booking.reload)

    expect(result.success?).to be true
    expect(result.filename).to eq("wastays-booking-summary-#{group.confirmation_token}.pdf")
  end
end
