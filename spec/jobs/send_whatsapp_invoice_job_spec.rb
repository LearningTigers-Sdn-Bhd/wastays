require "rails_helper"

RSpec.describe SendWhatsappInvoiceJob, type: :job do
  let(:hotel)     { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "pending",
      check_in: Date.current + 5.days,
      check_out: Date.current + 7.days,
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      quantity: 1,
      subtotal: 300.0,
      room_type_snapshot: { "name" => room_type.name }
    )
  end

  describe "#perform" do
    context "when webhook URL is configured" do
      before { AppConfig.set("webhook_url", "https://n8n.example.com/webhook/test") }

      it "POSTs to the configured URL" do
        stub = stub_request(:post, "https://n8n.example.com/webhook/test")
          .to_return(status: 200)

        described_class.new.perform(booking.id)

        expect(stub).to have_been_requested
      end

      it "sends correct payload fields" do
        stub = stub_request(:post, "https://n8n.example.com/webhook/test")
          .with(
            headers: { "Content-Type" => "application/json" },
            body: hash_including(
              "confirmation_token" => booking.confirmation_token,
              "guest_phone"        => booking.guest_phone,
              "guest_name"         => booking.guest_name,
              "hotel_name"         => hotel.name,
              "total_amount"       => format("%.2f", booking.total_amount.to_f)
            )
          )
          .to_return(status: 200)

        described_class.new.perform(booking.id)

        expect(stub).to have_been_requested
      end
    end

    context "when webhook URL is not configured" do
      before { AppConfig.find_by(key: "webhook_url")&.destroy }

      it "does not make any HTTP request" do
        expect(Net::HTTP).not_to receive(:start)
        described_class.new.perform(booking.id)
      end

      it "logs a warning" do
        expect(Rails.logger).to receive(:warn).with(/No webhook URL configured/)
        described_class.new.perform(booking.id)
      end
    end

    context "when booking does not exist" do
      it "silently returns without error" do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end
    end
  end
end
