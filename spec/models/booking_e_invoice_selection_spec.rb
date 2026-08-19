require "rails_helper"

RSpec.describe Booking, type: :model do
  describe "#latest_ready_guest_e_invoice_submission" do
    it "returns latest valid adjustment note ahead of original invoice" do
      booking = create(:booking)
      hotel = booking.hotel
      original = create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "01",
        status: "valid",
        created_at: 2.days.ago)
      adjustment = create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        document_scenario: "guest_invoice",
        document_type: "02",
        status: "valid",
        created_at: 1.day.ago)

      expect(booking.latest_ready_guest_e_invoice_submission).to eq(adjustment)
      expect(booking.latest_ready_guest_e_invoice_submission).not_to eq(original)
    end
  end
end
