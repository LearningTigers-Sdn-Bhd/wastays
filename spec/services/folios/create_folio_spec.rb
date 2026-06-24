# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CreateFolio do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let!(:guest_folio) { create(:booking_folio, hotel: hotel, booking: booking, folio_number: 101, name: "Guest Folio") }
  let!(:company_folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, folio_number: 102, name: "Company Folio") }

  it "creates a non-primary folio and records an operation log" do
    expect {
      @result = described_class.call(booking: booking, user: user, attributes: { name: "Incidentals", folio_type: "external", payer_type: "guest" })
    }.to change(BookingFolio, :count).by(1).and change(FolioOperationLog, :count).by(1)

    expect(@result).to be_success
    expect(@result.folio).not_to be_is_primary
    expect(@result.folio.name).to eq("Incidentals")
    expect(@result.folio.folio_sequence).to eq(3)
    expect(@result.folio.folio_reference_display).to eq("#{booking.reload.folio_account_reference_display}/3")
    expect(FolioOperationLog.last.operation_type).to eq("create_folio")
  end

  it "defaults new folios to external company payer" do
    result = described_class.call(booking: booking, user: user, attributes: {})

    expect(result).to be_success
    expect(result.folio.name).to eq("External Folio")
    expect(result.folio.folio_type).to eq("external")
    expect(result.folio.payer_type).to eq("company")
  end

  it "coerces locked guest and house payer types" do
    guest_result = described_class.call(booking: booking, user: user, attributes: { folio_type: "guest", payer_type: "company" })
    house_result = described_class.call(booking: booking, user: user, attributes: { folio_type: "house", payer_type: "custom" })

    expect(guest_result).to be_success
    expect(guest_result.folio.payer_type).to eq("guest")
    expect(house_result).to be_success
    expect(house_result.folio.payer_type).to eq("hotel")
  end

  it "does not change references when a new folio becomes primary" do
    original_account_reference = booking.reload.folio_account_reference_display
    original_guest_reference = guest_folio.reload.folio_reference_display

    result = described_class.call(
      booking: booking,
      user: user,
      attributes: {
        name: "Company Primary",
        folio_type: "external",
        payer_type: "company",
        is_primary: "1",
        set_folio_as_primary_reason: "Company pays"
      }
    )

    expect(result).to be_success
    expect(booking.reload.folio_account_reference_display).to eq(original_account_reference)
    expect(guest_folio.reload.folio_reference_display).to eq(original_guest_reference)
    expect(result.folio.reload).to be_is_primary
    expect(result.folio.folio_reference_display).to eq("#{original_account_reference}/3")
  end
end
