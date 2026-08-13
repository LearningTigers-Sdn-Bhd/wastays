# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParties::EnsureOta do
  let(:booking) { create(:booking) }
  let(:source) { create(:booking_source, kind: "ota") }

  it "creates one active OTA party for the source and reuses it" do
    party = described_class.call!(booking:, booking_source: source)

    expect(party).to be_persisted
    expect(party).to have_attributes(booking_id: booking.id, hotel_id: booking.hotel_id,
      party_kind: "ota", booking_source_id: source.id, archived_at: nil)
    expect { described_class.call!(booking:, booking_source: source) }
      .not_to change(BookingBillingParty, :count)
  end

  it "reactivates an archived identity" do
    party = create(:booking_billing_party, booking:, hotel: booking.hotel,
      party_kind: "ota", booking_source: source, booking_guest: nil, hotel_corporate_account: nil,
      archived_at: Time.current)

    expect(described_class.call!(booking:, booking_source: source)).to eq(party)
    expect(party.reload.archived_at).to be_nil
  end

  it "rejects non-OTA sources" do
    manual = create(:booking_source, kind: "manual")

    expect { described_class.call!(booking:, booking_source: manual) }
      .to raise_error(ArgumentError, /OTA/)
  end
end
