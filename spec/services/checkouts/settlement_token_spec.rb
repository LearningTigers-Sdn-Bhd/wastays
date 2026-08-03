# frozen_string_literal: true

require "rails_helper"

RSpec.describe Checkouts::SettlementToken do
  it "stores settlement amounts as positive values" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)

    token = described_class.issue(booking: booking, folio: folio, kind: "refund", amount: -50)

    expect(described_class.verify(token)).to include(
      booking_id: booking.id,
      folio_id: folio.id,
      kind: "refund",
      amount: "50.0"
    )
  end
end
