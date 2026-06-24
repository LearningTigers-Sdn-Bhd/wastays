# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ReopenFolio do
  let(:booking) { create(:booking, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel, status: "closed", closed_at: 1.hour.ago, closed_by: user) }

  it "reopens a closed folio and records the operation" do
    expect {
      @result = described_class.call(folio: folio, user: user, reason: "Correction required")
    }.to change(FolioOperationLog.where(operation_type: "reopen_folio"), :count).by(1)

    expect(@result).to be_success
    expect(folio.reload).to be_open
    expect(folio.closed_at).to be_nil
    expect(folio.closed_by).to be_nil
    expect(FolioOperationLog.last).to have_attributes(source_folio: folio, reason: "Correction required")
  end

  it "requires permission to manage folio windows" do
    result = described_class.call(folio: folio, user: create(:user))

    expect(result).not_to be_success
    expect(result.error).to include("permission")
    expect(folio.reload).to be_closed
  end

  it "rejects a folio that is not closed" do
    folio.update_column(:status, "open")

    expect(described_class.call(folio: folio, user: user).error).to eq("Only closed folios can be reopened.")
  end

  it "clears the temporary reopen authorization after success" do
    described_class.call(folio: folio, user: user)

    expect(folio.instance_variable_get(:@reopen_for_correction_authorized)).to be(false)
  end

  it "clears the temporary reopen authorization when persistence fails" do
    allow(folio).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(folio))

    result = described_class.call(folio: folio, user: user)

    expect(result).not_to be_success
    expect(folio.instance_variable_get(:@reopen_for_correction_authorized)).to be(false)
  end
end
