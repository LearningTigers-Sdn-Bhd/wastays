require "rails_helper"

RSpec.describe SendInvoiceEmailJob, type: :job do
  let(:hotel)     { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "pending",
      check_in: Date.current,
      check_out: Date.current + 2.days,
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      subtotal: 200.0,
      room_type_snapshot: { "name" => room_type.name }
    )
  end
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, status: "closed", invoice_number: 123) }

  describe "#perform" do
    it "delivers the invoice email for an existing booking" do
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 200)
      create(:folio_invoice, booking_folio: folio)

      expect {
        described_class.new.perform(booking.id)
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sends to the booking guest email" do
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 200)
      create(:folio_invoice, booking_folio: folio)

      described_class.new.perform(booking.id)
      last_email = ActionMailer::Base.deliveries.last
      expect(last_email.to).to include(booking.guest_email)
    end

    it "skips bookings without a closed folio" do
      expect(Rails.logger).to receive(:warn).with(/SendInvoiceEmailJob skipped booking #{booking.id}/)

      expect {
        described_class.new.perform(booking.id)
      }.not_to change { ActionMailer::Base.deliveries.count }
    end

    it "silently returns when booking does not exist" do
      expect { described_class.new.perform(999999) }.not_to raise_error
    end
  end
end
