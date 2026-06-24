# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CloseFolio do
  let(:booking) { create(:booking, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel, status: "open") }

  it "closes a zero-balance folio and records the operation" do
    expect {
      @result = described_class.call(folio: folio, user: user, reason: "Settled")
    }.to change(FolioOperationLog.where(operation_type: "close_folio"), :count).by(1)

    expect(@result).to be_success
    expect(folio.reload).to be_closed
    expect(folio.closed_at).to be_present
    expect(folio.closed_by).to eq(user)
    expect(FolioOperationLog.last).to have_attributes(source_folio: folio, reason: "Settled")
  end

  it "requires permission to manage folio windows" do
    result = described_class.call(folio: folio, user: create(:user))

    expect(result).not_to be_success
    expect(result.error).to include("permission")
    expect(folio.reload).to be_open
  end

  it "rejects a folio that is already closed" do
    folio.update!(status: "closed")

    expect(described_class.call(folio: folio, user: user).error).to eq("Folio is already closed.")
  end

  it "rejects a folio with pending forecasts" do
    create(:folio_forecasted_charge, booking_folio: folio)

    expect(described_class.call(folio: folio, user: user).error).to eq("Cannot close a folio with pending upcoming charges.")
    expect(folio.reload).to be_open
  end

  it "rejects a folio with a non-zero balance" do
    create(:folio_transaction, booking_folio: folio, amount: 125)

    expect(described_class.call(folio: folio, user: user).error).to eq("Cannot close folio with non-zero balance of MYR 125.00.")
    expect(folio.reload).to be_open
  end
end
