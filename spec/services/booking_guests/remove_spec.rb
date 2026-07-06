# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuests::Remove do
  let(:booking) { create(:booking) }
  let(:actor) { create(:user) }

  it "removes an additional guest with no financial ownership" do
    booking_guest = create(:booking_guest, booking: booking, is_primary: false)

    expect { described_class.call(booking_guest: booking_guest, actor: actor) }
      .to change(BookingGuest, :count).by(-1).and change(BookingBillingParty, :count).by(-1)
  end

  it "blocks removal when the guest billing party owns a folio" do
    booking_guest = create(:booking_guest, booking: booking, is_primary: false)
    create(:booking_folio, booking: booking, hotel: booking.hotel,
      booking_billing_party: booking_guest.booking_billing_party, is_primary: false)

    result = described_class.call(booking_guest: booking_guest, actor: actor)

    expect(result).not_to be_success
    expect(result.error).to include("Reassign")
    expect(booking_guest).to be_persisted
  end
end
