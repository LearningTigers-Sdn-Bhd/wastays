# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::MonthlyOtaCommissionJob, type: :job do
  let(:hotel) { create(:hotel) }
  let!(:setting) do
    create(:e_invoice_setting, hotel: hotel, enabled: true,
      hotel_tin: "C9988776655", hotel_brn: "202399887766")
  end
  let(:last_month) { Date.current.prev_month.beginning_of_month }
  let(:run_date) { Date.current.beginning_of_month }
  let(:client) { instance_double(MyInvois::MockClient) }

  before do
    BookingSource.seed_defaults!
    setting.update_column(:effective_from, last_month.beginning_of_month - 1.day)
    allow(MyInvois::ClientFactory).to receive(:build).and_return(client)
    # LHDN returns a distinct UUID per document, and the schema enforces that.
    allow(client).to receive(:submit_documents) do
      { "submissionUid" => SecureRandom.uuid, "acceptedDocuments" => [ { "uuid" => SecureRandom.uuid } ] }
    end
  end

  def ota_stay(source:, total:, net:, checked_out: last_month + 5.days)
    create(:booking, hotel: hotel, source: source, status: "completed",
      total_amount: total, net_amount: net, checked_out_at: checked_out)
  end

  # Agoda and Booking.com are overseas, so LHDN sees no invoice from them; the
  # hotel self-bills to deduct the commission as an imported service.
  it "files one self-billed document per OTA for the month" do
    ota_stay(source: "agoda", total: 720.0, net: 633.60)
    ota_stay(source: "agoda", total: 500.0, net: 440.00)
    ota_stay(source: "booking_com", total: 300.0, net: 255.00)

    expect { described_class.new.perform(run_date) }
      .to change(EInvoiceSubmission.where(document_scenario: "ota_commission_self_billed"), :count).by(2)

    agoda = EInvoiceSubmission.find_by(ota_source_key: "agoda")
    expect(agoda.document_type).to eq("11")
    expect(agoda.status).to eq("submitted")
    expect(agoda.supplier_name).to eq("Agoda Company Pte. Ltd.")
    expect(agoda.period_start).to eq(last_month)
  end

  # Otherwise the document sits at "submitted" and is never confirmed.
  it "polls LHDN for the outcome after filing" do
    ota_stay(source: "agoda", total: 720.0, net: 633.60)

    expect { described_class.new.perform(run_date) }
      .to have_enqueued_job(EInvoice::RefreshStatusJob)
  end

  it "leaves direct bookings out of it" do
    ota_stay(source: "walk_in", total: 720.0, net: 633.60)

    expect { described_class.new.perform(run_date) }
      .not_to change(EInvoiceSubmission, :count)
  end

  it "ignores stays outside the month being closed" do
    ota_stay(source: "agoda", total: 720.0, net: 633.60, checked_out: last_month - 2.months)

    expect { described_class.new.perform(run_date) }
      .not_to change(EInvoiceSubmission, :count)
  end

  it "does not file again for a month already accepted" do
    ota_stay(source: "agoda", total: 720.0, net: 633.60)
    described_class.new.perform(run_date)

    expect { described_class.new.perform(run_date) }
      .not_to change(EInvoiceSubmission, :count)
  end

  it "skips a stay whose commission is nil or zero" do
    ota_stay(source: "agoda", total: 720.0, net: 720.0)

    expect { described_class.new.perform(run_date) }
      .not_to change(EInvoiceSubmission, :count)
  end

  # Commission is owed whoever held the money.
  it "bills commission on a pay-at-hotel stay too" do
    booking = ota_stay(source: "agoda", total: 720.0, net: 633.60)
    settlement = create(:channel_settlement, hotel: hotel, collection_by: "property")
    create(:channel_settlement_allocation, channel_settlement: settlement, booking: booking)

    described_class.new.perform(run_date)

    expect(EInvoiceSubmission.find_by(ota_source_key: "agoda")).to be_present
  end
end
