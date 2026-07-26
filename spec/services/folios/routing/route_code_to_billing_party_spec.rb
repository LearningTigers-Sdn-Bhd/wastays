# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::RouteCodeToBillingParty do
  let(:booking) { create(:booking) }
  let(:hotel) { booking.hotel }
  let!(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }
  let(:room_code) { hotel.transaction_codes.find_by!(system_key: "room_revenue") }

  it "creates an active rule routing the code to the target folio" do
    result = described_class.call(booking: booking, transaction_code: room_code, target_folio: company_folio)

    expect(result.success?).to be(true)
    expect(result.rule).to have_attributes(transaction_code_id: room_code.id, target_folio_id: company_folio.id, active: true)
  end

  it "reuses the active rule instead of creating a duplicate" do
    first = described_class.call(booking: booking, transaction_code: room_code, target_folio: company_folio)
    second = described_class.call(booking: booking, transaction_code: room_code, target_folio: company_folio)

    expect(second.success?).to be(true)
    expect(second.rule.id).to eq(first.rule.id)
    expect(booking.folio_routing_rules.active.where(transaction_code: room_code).count).to eq(1)
  end

  it "rejects a closed target folio" do
    company_folio.update!(status: "closed")

    result = described_class.call(booking: booking, transaction_code: room_code, target_folio: company_folio)

    expect(result.success?).to be(false)
    expect(result.error).to match(/open/i)
  end

  it "requires a transaction code and target folio" do
    expect(described_class.call(booking: booking, transaction_code: nil, target_folio: company_folio).success?).to be(false)
    expect(described_class.call(booking: booking, transaction_code: room_code, target_folio: nil).success?).to be(false)
  end
end
