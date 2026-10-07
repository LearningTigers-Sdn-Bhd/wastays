require "rails_helper"

RSpec.describe NightAudits::Evaluation::Checks::OutstandingFolioBalances do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:business_date) { hotel.current_business_date }
  let(:booking) { create(:booking, hotel:, status: "completed", check_in: business_date - 1.day, check_out: business_date) }
  let(:context) { NightAudits::Evaluation::Context.new(hotel:, business_date:, phase: :post_close) }
  let!(:primary_folio) { create(:booking_folio, booking:, hotel:) }

  def blockers
    described_class.new(context:).call.fetch("outstanding_folio_balance")
  end

  def charged_company_folio
    create(:booking_folio, :secondary, booking:, hotel:).tap do |folio|
      create(:folio_transaction, booking_folio: folio, amount: 100)
    end
  end

  it "is registered for every evaluation phase" do
    expect(NightAudits::Evaluate::PRE_CLOSE_CHECKS).to include(described_class)
    expect(NightAudits::Evaluate::POST_CLOSE_CHECKS).to include(described_class)
  end

  %w[open partially_paid paid overdue].each do |status|
    it "accepts a closed Direct Bill transfer with a #{status} receivable" do
      folio = charged_company_folio
      folio.update!(status: "closed", closed_at: Time.current)
      paid = { "open" => 0, "partially_paid" => 40, "paid" => 100, "overdue" => 0 }.fetch(status)
      create(:ar_invoice, booking_folio: folio, amount: 100, status:, paid_amount: paid, outstanding_amount: 100 - paid)

      expect(blockers).to be_empty
      expect(folio.outstanding_balance).to eq(100)
    end
  end

  it "accepts a legacy receivable without a linked invoice" do
    folio = charged_company_folio
    folio.update!(status: "closed", closed_at: Time.current)
    create(:ar_invoice, booking_folio: folio, amount: 100).update_column(:invoice_id, nil)

    expect(blockers).to be_empty
  end

  it "blocks an open company folio even when a receivable exists" do
    folio = charged_company_folio
    create(:ar_invoice, booking_folio: folio, amount: 100)

    expect(blockers.pluck("booking_id")).to eq([ booking.id ])
  end

  it "blocks a closed company folio without a receivable" do
    charged_company_folio.update!(status: "closed", closed_at: Time.current)

    expect(blockers.pluck("booking_id")).to eq([ booking.id ])
  end

  it "blocks a void receivable" do
    folio = charged_company_folio
    folio.update!(status: "closed", closed_at: Time.current)
    create(:ar_invoice, booking_folio: folio, amount: 100, status: "void")

    expect(blockers.pluck("booking_id")).to eq([ booking.id ])
  end

  %i[amount currency hotel_id hotel_corporate_account_id].each do |field|
    it "blocks a transfer with mismatched #{field}" do
      folio = charged_company_folio
      folio.update!(status: "closed", closed_at: Time.current)
      receivable = create(:ar_invoice, booking_folio: folio, amount: 100)
      value = case field
      when :amount then 90
      when :currency then "USD"
      when :hotel_id then create(:hotel).id
      when :hotel_corporate_account_id then create(:hotel_corporate_account, hotel:).id
      end
      receivable.update_column(field, value)

      expect(blockers.pluck("booking_id")).to eq([ booking.id ])
    end
  end

  it "blocks guest debt even alongside a valid company transfer" do
    folio = charged_company_folio
    folio.update!(status: "closed", closed_at: Time.current)
    create(:ar_invoice, booking_folio: folio, amount: 100)
    create(:folio_transaction, booking_folio: primary_folio, amount: 30)

    expect(blockers.pluck("booking_id")).to eq([ booking.id ])
  end

  it "does not offset a secondary debt against a primary credit" do
    charged_company_folio
    create(:folio_transaction, booking_folio: primary_folio, transaction_type: "payment", category: "cash", amount: 100)

    expect(blockers.pluck("booking_id")).to eq([ booking.id ])
  end

  it "blocks a negative company balance even with a receivable" do
    folio = charged_company_folio
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 150)
    folio.update!(status: "closed", closed_at: Time.current)
    create(:ar_invoice, booking_folio: folio, amount: 100)

    expect(blockers.pluck("booking_id")).to eq([ booking.id ])
  end
end
