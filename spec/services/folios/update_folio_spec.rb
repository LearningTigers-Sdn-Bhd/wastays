# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::UpdateFolio do
  let(:booking) { create(:booking, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel) }
  let(:hotel_corporate_account) { create(:hotel_corporate_account, hotel: booking.hotel) }

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
    expect(folio.hotel_corporate_account).to be_nil
  end

  it "assigns a Company & Government account and logs it" do
    result = described_class.call(
      folio: folio,
      user: user,
      attributes: {
        folio_type: "external",
        payer_type: "company",
        hotel_corporate_account_id: hotel_corporate_account.id,
        reason: "Bill company"
      }
    )

    expect(result).to be_success
    expect(folio.reload.hotel_corporate_account).to eq(hotel_corporate_account)
    expect(FolioOperationLog.last.metadata.dig("changes", "hotel_corporate_account_id", "to")).to eq(hotel_corporate_account.id)
  end

  it "rejects Company & Government accounts from another hotel" do
    other_relationship = create(:hotel_corporate_account)

    result = described_class.call(
      folio: folio,
      user: user,
      attributes: { folio_type: "external", payer_type: "company", hotel_corporate_account_id: other_relationship.id }
    )

    expect(result).not_to be_success
    expect(result.error).to include("must belong to the folio hotel")
  end
end
