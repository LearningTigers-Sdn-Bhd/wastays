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

RSpec.describe "Booking e-invoice automation", type: :model do
  let(:hotel) { create(:hotel) }

  # Payment concluding is what starts the e-invoice lifecycle. Without these
  # hooks the >=RM10,000 rule never fires and the monthly consolidation has no
  # placeholders to collect, so the feature silently files nothing.
  context "when the hotel has e-invoicing enabled" do
    before { create(:e_invoice_setting, hotel: hotel, enabled: true) }

    it "enqueues auto-issue when a booking is created already paid" do
      expect {
        create(:booking, hotel: hotel, payment_status: "captured")
      }.to have_enqueued_job(EInvoice::AutoIssueJob)
    end

    it "enqueues auto-issue when payment status later becomes captured" do
      booking = create(:booking, hotel: hotel, payment_status: "pending")

      expect {
        booking.update!(payment_status: "captured")
      }.to have_enqueued_job(EInvoice::AutoIssueJob).with(booking.id)
    end

    it "does not enqueue again when an unrelated attribute changes" do
      booking = create(:booking, hotel: hotel, payment_status: "captured")

      expect {
        booking.update!(guest_name: "Someone Else")
      }.not_to have_enqueued_job(EInvoice::AutoIssueJob)
    end
  end

  it "stays out of the way when the hotel has e-invoicing turned off" do
    expect {
      create(:booking, hotel: hotel, payment_status: "captured")
    }.not_to have_enqueued_job(EInvoice::AutoIssueJob)
  end
end

RSpec.describe "Booking buyer TIN resolution", type: :model do
  let(:hotel) { create(:hotel) }

  # Whoever is being billed is who claims the invoice, so the company's TIN
  # wins over the individual traveller's.
  it "prefers the corporate account's TIN when the company is billed" do
    account = create(:account, :corporate)
    corporate = create(:hotel_corporate_account, hotel: hotel, corporate_account: account, tin: "C9999999999")
    booking = create(:booking, hotel: hotel, hotel_corporate_account: corporate, guest_tin: "IG1111111111")

    expect(booking.buyer_tin_for_e_invoice).to eq("C9999999999")
  end

  it "uses the TIN captured on the booking for an individual guest" do
    booking = create(:booking, hotel: hotel, guest_tin: "IG1111111111")

    expect(booking.buyer_tin_for_e_invoice).to eq("IG1111111111")
  end

  it "falls back to the matched guest record's TIN" do
    guest = create(:guest, tin: "IG2222222222")
    booking = create(:booking, hotel: hotel, guest_tin: nil)
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)

    expect(booking.reload.buyer_tin_for_e_invoice).to eq("IG2222222222")
  end

  it "is nil when nobody supplied one, so the builder files as general public" do
    booking = create(:booking, hotel: hotel)

    expect(booking.buyer_tin_for_e_invoice).to be_nil
  end
end
