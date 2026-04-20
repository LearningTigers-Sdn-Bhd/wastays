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
      quantity: 1,
      subtotal: 200.0,
      room_type_snapshot: { "name" => room_type.name }
    )
  end

  describe "#perform" do
    it "delivers the invoice email for an existing booking" do
      expect {
        described_class.new.perform(booking.id)
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sends to the booking guest email" do
      described_class.new.perform(booking.id)
      last_email = ActionMailer::Base.deliveries.last
      expect(last_email.to).to include(booking.guest_email)
    end

    it "silently returns when booking does not exist" do
      expect { described_class.new.perform(999999) }.not_to raise_error
    end
  end
end
