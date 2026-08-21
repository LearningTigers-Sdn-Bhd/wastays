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

RSpec.describe "Booking e-invoice buyer readiness", type: :model do
  let(:hotel) { create(:hotel) }
  let!(:setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }
  let(:booking) do
    create(:booking, hotel: hotel, payment_status: "captured",
      guest_city: "Petaling Jaya", guest_state_code: "10", guest_tin: "IG12345678901")
  end

  before { create(:payment_transaction, booking: booking, status: "captured", captured_at: Time.current) }

  it "is ready when the buyer has a city and a resolvable state" do
    expect(booking.e_invoice_buyer_details_missing).to be_empty
  end

  # Blocked at the point of asking, so the guest can still fix it, rather than
  # accepted and rejected by LHDN days later.
  it "names the missing state so the guest can be told" do
    booking.update!(guest_state_code: nil, guest_city: "Nowhereville")

    expect(booking.e_invoice_buyer_details_missing).to include("state")
    expect(booking.e_invoice_guest_request_possible?).to be(false)
  end

  it "names a missing city" do
    booking.update!(guest_city: nil, guest_state_code: "10")

    expect(booking.e_invoice_buyer_details_missing).to include("city")
  end

  it "accepts a city the old lookup knew, without an explicit state" do
    booking.update!(guest_state_code: nil, guest_city: "Kota Kinabalu")

    expect(booking.e_invoice_buyer_details_missing).to be_empty
  end
end

RSpec.describe "Booking OTA e-invoice treatment", type: :model do
  let(:hotel) { create(:hotel) }
  let!(:setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }

  before { BookingSource.seed_defaults! }

  # On an OTA stay the hotel sells to the OTA, not to the guest.
  it "recognises an OTA source from the booking source registry" do
    expect(build(:booking, hotel: hotel, source: "agoda").ota_booking?).to be(true)
    expect(build(:booking, hotel: hotel, source: "booking_com").ota_booking?).to be(true)
    expect(build(:booking, hotel: hotel, source: "walk_in").ota_booking?).to be(false)
    expect(build(:booking, hotel: hotel, source: "direct").ota_booking?).to be(false)
  end

  it "treats the catch-all 'ota' source as an OTA" do
    expect(build(:booking, hotel: hotel, source: "ota").ota_booking?).to be(true)
  end

  def ota_stay(collection_by:, total: 720.0, net: 633.60)
    booking = create(:booking, hotel: hotel, source: "agoda", payment_status: "captured",
      total_amount: total, net_amount: net,
      guest_city: "Kuala Lumpur", guest_state_code: "14", guest_tin: "IG12345678901")
    create(:payment_transaction, booking: booking, status: "captured", captured_at: Time.current)
    if collection_by
      settlement = create(:channel_settlement, hotel: hotel, collection_by: collection_by)
      create(:channel_settlement_allocation, channel_settlement: settlement, booking: booking)
    end
    booking.reload
  end

  # Arriving through Agoda is not the same as Agoda taking the money.
  it "counts the stay as OTA-collected only when settlement says so" do
    expect(ota_stay(collection_by: "ota").ota_collected?).to be(true)
    expect(ota_stay(collection_by: "property").ota_collected?).to be(false)
  end

  it "assumes the hotel collected when there is no settlement data" do
    expect(ota_stay(collection_by: nil).ota_collected?).to be(false)
  end

  # Prepaid: the OTA paid the hotel net, and that is the hotel's sale.
  it "files an OTA-collected stay at net" do
    expect(ota_stay(collection_by: "ota").e_invoice_amount).to eq(633.60)
  end

  # Pay at hotel: the guest handed over the full amount at the front desk.
  it "files a pay-at-hotel stay at gross, commission being a separate expense" do
    expect(ota_stay(collection_by: "property").e_invoice_amount).to eq(720.0)
  end

  it "reports the commission the OTA keeps" do
    expect(ota_stay(collection_by: "ota").ota_commission_amount).to eq(86.40)
  end

  it "denies a guest request only when the OTA took the money" do
    expect(ota_stay(collection_by: "ota").e_invoice_guest_request_possible?).to be(false)
  end

  # This guest is the hotel's customer and may claim the stay.
  it "lets a pay-at-hotel guest request an individual e-invoice" do
    expect(ota_stay(collection_by: "property").e_invoice_guest_request_possible?).to be(true)
  end
end
