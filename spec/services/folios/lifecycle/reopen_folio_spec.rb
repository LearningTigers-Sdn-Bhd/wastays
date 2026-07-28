# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::ReopenFolio do
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

  it "marks an issued invoice under correction" do
    issued_folio = create(:booking_folio, booking: booking, hotel: booking.hotel, status: "open")
    close_result = Folios::Lifecycle::CloseFolio.call(folio: issued_folio, user: user, reason: "Settled")

    result = described_class.call(folio: close_result.folio, user: user, reason: "Posting correction")

    expect(result).to be_success
    expect(issued_folio.reload).to be_open
    expect(issued_folio.invoice).to be_under_correction
  end

  it "creates the next immutable revision when the corrected folio closes again" do
    issued_folio = create(:booking_folio, booking: booking, hotel: booking.hotel, status: "open")
    Folios::Lifecycle::CloseFolio.call(folio: issued_folio, user: user, reason: "Settled")
    base_reference = issued_folio.reload.invoice.invoice_reference
    described_class.call(folio: issued_folio, user: user, reason: "Posting correction")

    result = Folios::Lifecycle::CloseFolio.call(folio: issued_folio.reload, user: user, reason: "Correction complete")

    expect(result).to be_success
    invoice = issued_folio.reload.invoice
    expect(invoice).to be_finalized
    expect(invoice.current_revision_number).to eq(2)
    expect(invoice.current_document_reference).to eq("#{base_reference}-2")
    expect(invoice.revisions.pluck(:revision_number)).to eq([ 1, 2 ])
  end

  it "requires a reason when an issued invoice exists" do
    issued_folio = create(:booking_folio, booking: booking, hotel: booking.hotel, status: "open")
    Folios::Lifecycle::CloseFolio.call(folio: issued_folio, user: user, reason: "Settled")

    result = described_class.call(folio: issued_folio.reload, user: user)

    expect(result.error).to eq("Reason is required to reopen an invoiced folio.")
    expect(issued_folio.reload).to be_closed
  end

  it "blocks reopening a folio with an active AR invoice" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel,
      hotel_corporate_account: relationship, status: "closed", closed_at: Time.current)
    create(:ar_invoice, booking_folio: company_folio, hotel: booking.hotel, hotel_corporate_account: relationship)

    result = described_class.call(folio: company_folio, user: user, reason: "Correction")

    expect(result.error).to include("Accounts Receivable")
    expect(company_folio.reload).to be_closed
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

  # The authorization must not outlive the service call — otherwise the folio
  # instance would go on accepting unguarded reopens for the rest of the request.
  it "leaves the reopen guard back in force after success" do
    described_class.call(folio: folio, user: user)
    folio.update_column(:status, "closed")

    expect(folio.update(status: "open")).to be(false)
    expect(folio.errors[:status]).to include("can only be reopened through the controlled correction workflow")
  end

  it "leaves the reopen guard back in force when persistence fails" do
    allow(folio).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(folio))

    result = described_class.call(folio: folio, user: user)

    expect(result).not_to be_success
    allow(folio).to receive(:update!).and_call_original
    expect(folio.update(status: "open")).to be(false)
    expect(folio.errors[:status]).to include("can only be reopened through the controlled correction workflow")
  end
end
