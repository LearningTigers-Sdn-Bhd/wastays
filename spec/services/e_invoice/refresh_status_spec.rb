require "rails_helper"

RSpec.describe EInvoice::RefreshStatus, type: :service do
  describe ".call" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel, booking_quote: nil) }
    let(:submission) do
      create(:e_invoice_submission,
        hotel: hotel,
        booking: booking,
        status: "valid",
        uuid: "uuid-123",
        validated_at: 1.day.ago)
    end
    let(:client) { double("MyInvois::Client") }

    before do
      allow(MyInvois::ClientFactory).to receive(:build).and_return(client)
    end

    it "clears validated_at when status becomes invalid" do
      allow(client).to receive(:get_document_details).and_return({
        "status" => "Invalid",
        "longId" => "long-123"
      })

      result = described_class.call(submission)

      expect(result[:success]).to be true
      expect(submission.reload.status).to eq("invalid")
      expect(submission.validated_at).to be_nil
    end
  end
end
