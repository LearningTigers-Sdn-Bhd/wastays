require "rails_helper"

RSpec.describe EInvoice::SelectGuestSubmission do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel) }

  it "gives the latest ready submission when no id is named" do
    ready = create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", document_type: "01")

    expect(described_class.new(booking: booking).call).to eq(ready)
  end

  it "gives the named submission so a guest can open an older document" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", document_type: "02")
    original = create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", document_type: "01")

    result = described_class.new(booking: booking, submission_id: original.id).call

    expect(result).to eq(original)
  end

  it "gives nothing for an id on another booking" do
    other = create(:booking, hotel: hotel)
    stranger = create(:e_invoice_submission, hotel: hotel, booking: other, status: "valid", document_type: "01")

    expect(described_class.new(booking: booking, submission_id: stranger.id).call).to be_nil
  end

  it "gives nothing when the booking has no submission" do
    expect(described_class.new(booking: booking).call).to be_nil
  end
end
