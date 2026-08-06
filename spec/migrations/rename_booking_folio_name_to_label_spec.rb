# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260726120000_rename_booking_folio_name_to_label")

RSpec.describe RenameBookingFolioNameToLabel do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }

  def clear_generated_labels!
    described_class.new.send(:clear_generated_labels!)
  end

  it "clears the labels the app used to generate" do
    guest = create(:booking_folio, hotel: hotel, booking: booking, label: "Guest Folio")
    numbered = create(:booking_folio, :secondary, hotel: hotel, booking: booking, label: "Folio 42")

    clear_generated_labels!

    expect(guest.reload.label).to be_nil
    expect(numbered.reload.label).to be_nil
  end

  it "keeps a label a human chose" do
    folio = create(:booking_folio, hotel: hotel, booking: booking, label: "Honeymoon extras")

    clear_generated_labels!

    expect(folio.reload.label).to eq("Honeymoon extras")
  end

  it "keeps a generated-looking label once it has been renamed by hand" do
    folio = create(:booking_folio, hotel: hotel, booking: booking, label: "Guest Folio")
    create(
      :folio_operation_log,
      hotel: hotel,
      booking: booking,
      operation_type: "rename_folio",
      source_folio: folio,
      target_folio: folio
    )

    clear_generated_labels!

    expect(folio.reload.label).to eq("Guest Folio")
  end

  it "clears labels derived from the linked billing party" do
    party = create(:booking_guest, booking: booking).booking_billing_party
    folio = create(
      :booking_folio,
      hotel: hotel,
      booking: booking,
      booking_billing_party: party,
      label: "#{party.display_name} Folio"
    )

    clear_generated_labels!

    expect(folio.reload.label).to be_nil
  end
end
