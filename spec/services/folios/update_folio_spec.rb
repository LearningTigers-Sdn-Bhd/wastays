# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::UpdateFolio do
  let(:booking) { create(:booking, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel) }

  it "coerces locked payer types and logs the normalized values" do
    result = described_class.call(
      folio: folio,
      user: user,
      attributes: {
        folio_type: "house",
        payer_type: "company",
        reason: "House use"
      }
    )

    expect(result).to be_success
    expect(folio.reload).to be_folio_type_house
    expect(folio.payer_type).to eq("hotel")
    expect(FolioOperationLog.last.metadata.dig("changes", "payer_type", "to")).to eq("hotel")
  end
end
