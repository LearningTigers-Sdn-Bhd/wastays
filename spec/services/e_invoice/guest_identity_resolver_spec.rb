# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::GuestIdentityResolver do
  describe ".from_values" do
    it "sends a MyKad number as an NRIC" do
      result = described_class.from_values(
        document_type: "malaysian_nric", document_number: "880101015432", country: "Malaysia"
      )

      expect(result.document_type).to eq("ic")
      expect(result.document_number).to eq("880101015432")
      expect(result).not_to be_missing_passport
    end

    it "sends the passport number for a foreign national identity card" do
      result = described_class.from_values(
        document_type: "national_id", document_number: "S1234567",
        passport_number: "E9988776", country: "Singapore"
      )

      expect(result.document_type).to eq("passport")
      expect(result.document_number).to eq("E9988776")
      expect(result).not_to be_missing_passport
    end

    it "reports a missing passport when a foreign guest gives no passport number" do
      result = described_class.from_values(
        document_type: "national_id", document_number: "S1234567", country: "Singapore"
      )

      expect(result.document_number).to be_nil
      expect(result).to be_missing_passport
    end

    it "reads an old ic value as a MyKad" do
      result = described_class.from_values(
        document_type: "ic", document_number: "880101015432", country: "Malaysia"
      )

      expect(result.document_type).to eq("ic")
    end
  end

  describe ".for_guest" do
    it "reads the passport number from the guest profile" do
      guest = create(:guest, country: "Singapore", document_type: "national_id",
        government_id: "S1234567", passport_number: "E1111111", date_of_birth: Date.new(1990, 1, 1))

      result = described_class.for_guest(guest)

      expect(result.document_type).to eq("passport")
      expect(result.document_number).to eq("e1111111")
    end
  end

  describe ".for_booking" do
    it "prefers the stay snapshot over the guest profile" do
      guest = create(:guest, country: "Singapore", document_type: "national_id",
        government_id: "S1234567", passport_number: "E1111111", date_of_birth: Date.new(1990, 1, 1))
      booking = create(:booking, guest_country: "Singapore", guest_document_type: "national_id",
        guest_government_id: "S1234567")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      booking_guest.update!(passport_number_snapshot: "E2222222")

      result = described_class.for_booking(booking.reload)

      expect(result.document_number).to eq("E2222222")
    end
  end
end
