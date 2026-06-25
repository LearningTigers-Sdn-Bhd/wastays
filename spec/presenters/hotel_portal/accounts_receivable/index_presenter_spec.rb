# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::IndexPresenter do
  subject(:presenter) { described_class.new(hotel: hotel, params: params) }

  let(:hotel) { create(:hotel, status: "approved", default_currency: "MYR") }
  let(:params) { {} }
  let(:business_date) { hotel.current_business_date }

  describe "filtering and pagination" do
    let(:first_relationship) do
      create(:hotel_corporate_account, hotel: hotel, corporate_account: create(:account, :corporate, name: "Atlas Holdings"))
    end
    let(:second_relationship) do
      create(:hotel_corporate_account, hotel: hotel, corporate_account: create(:account, :corporate, name: "Beacon Group"))
    end

    before do
      create_invoice(
        relationship: first_relationship,
        confirmation_token: "BK-ATLAS",
        folio_number: 411,
        status: "open",
        due_on: business_date + 3.days
      )
      create_invoice(
        relationship: second_relationship,
        confirmation_token: "BK-BEACON",
        folio_number: 822,
        status: "paid",
        due_on: business_date + 10.days,
        amount: 75,
        paid_amount: 75,
        outstanding_amount: 0
      )
    end

    it "filters by searchable invoice data" do
      atlas_invoice = hotel.ar_invoices.find_by!(hotel_corporate_account: first_relationship)

      expect(presenter_for(query: atlas_invoice.invoice_number.to_s).paginated_rows.map(&:booking_reference)).to eq([ "BK-ATLAS" ])
      expect(presenter_for(query: "Atlas").paginated_rows.map(&:booking_reference)).to eq([ "BK-ATLAS" ])
      expect(presenter_for(query: "BK-BEACON").paginated_rows.map(&:booking_reference)).to eq([ "BK-BEACON" ])
      expect(presenter_for(query: "411").paginated_rows.map(&:booking_reference)).to eq([ "BK-ATLAS" ])
    end

    it "combines corporate account, exact due date, and status filters" do
      filtered = presenter_for(
        hotel_corporate_account_id: first_relationship.id,
        due_on: (business_date + 3.days).iso8601,
        status: "open"
      )

      expect(filtered.paginated_rows.map(&:booking_reference)).to eq([ "BK-ATLAS" ])
      expect(filtered.filters_active?).to be(true)
    end

    it "ignores invalid account, status, and date filters without escaping hotel scope" do
      other_hotel = create(:hotel, status: "approved")
      create_invoice(hotel: other_hotel, confirmation_token: "BK-HIDDEN", folio_number: 999)

      invalid = presenter_for(
        hotel_corporate_account_id: "999999",
        status: "not-a-status",
        due_on: "not-a-date"
      )

      expect(invalid.paginated_rows.map(&:booking_reference)).to contain_exactly("BK-ATLAS", "BK-BEACON")
      expect(invalid.filters_active?).to be(false)
    end

    it "paginates rows at 25 invoices" do
      24.times do |index|
        create_invoice(
          relationship: first_relationship,
          confirmation_token: "BK-PAGE-#{index}",
          folio_number: 1_000 + index,
          due_on: business_date + 30.days
        )
      end

      expect(presenter.paginated_rows.size).to eq(25)
      expect(presenter.pagination.total_pages).to eq(2)
    end
  end

  describe "summary metrics" do
    it "groups open, overdue, due-soon, and monthly received totals by currency" do
      relationship = create(:hotel_corporate_account, hotel: hotel)
      create_invoice(relationship: relationship, amount: 100, due_on: business_date - 1.day, status: "overdue")
      create_invoice(relationship: relationship, amount: 80, due_on: business_date + 7.days)
      create_invoice(relationship: relationship, amount: 60, due_on: business_date + 8.days)
      create_invoice(relationship: relationship, amount: 50, currency: "USD", due_on: business_date + 2.days)
      create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 125, currency: "MYR", received_at: business_date)
      create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 40, currency: "USD", received_at: business_date)
      create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 999, currency: "MYR", received_at: business_date.prev_month)

      metrics = presenter.summary_metrics.index_by(&:label)

      expect(metrics.fetch("Open AR").amounts).to eq([ "MYR 240.00", "USD 50.00" ])
      expect(metrics.fetch("Overdue").amounts).to eq([ "MYR 100.00" ])
      expect(metrics.fetch("Due Soon").amounts).to eq([ "MYR 80.00", "USD 50.00" ])
      expect(metrics.fetch("Paid This Month").amounts).to eq([ "MYR 125.00", "USD 40.00" ])
    end

    it "shows a zero value in the hotel's default currency when a metric has no records" do
      expect(presenter.summary_metrics).to all(satisfy { |metric| metric.amounts == [ "MYR 0.00" ] })
    end
  end

  describe "row presentation" do
    it "formats invoice labels, financial values, dates, source references, and status styles" do
      relationship = create(
        :hotel_corporate_account,
        hotel: hotel,
        corporate_account: create(:account, :corporate, name: "Northstar Travel")
      )
      invoice = create_invoice(
        relationship: relationship,
        confirmation_token: "BK-NORTH",
        folio_number: 744,
        amount: 250,
        paid_amount: 100,
        outstanding_amount: 150,
        status: "partially_paid",
        issued_on: Date.new(2026, 6, 1),
        due_on: Date.new(2026, 6, 30)
      )

      row = described_class::Row.new(invoice)

      expect(row.invoice_label).to eq("AR-#{invoice.invoice_number}")
      expect(row.corporate_account_name).to eq("Northstar Travel")
      expect(row.booking_reference).to eq("BK-NORTH")
      expect(row.folio_reference).to include("744")
      expect(row.source_label).to eq("Booking BK-NORTH · Folio #{row.folio_reference}")
      expect(row.issued_on_label).to eq("01 Jun 2026")
      expect(row.due_on_label).to eq("30 Jun 2026")
      expect(row.outstanding_amount_label).to eq("MYR 150.00")
      expect(row.status_label).to eq("Partially paid")
      expect(row.status_class).to include("bg-amber-50")
    end
  end

  def presenter_for(overrides)
    described_class.new(hotel: hotel, params: overrides)
  end

  def create_invoice(
    hotel: self.hotel,
    relationship: nil,
    confirmation_token: "BK-AR-#{SecureRandom.hex(3)}",
    folio_number: rand(10_000..99_999),
    amount: 100,
    paid_amount: 0,
    outstanding_amount: amount,
    currency: "MYR",
    status: "open",
    issued_on: business_date,
    due_on: business_date + 30.days
  )
    relationship ||= create(:hotel_corporate_account, hotel: hotel)
    booking = create(:booking, hotel: hotel, confirmation_token: confirmation_token, currency: currency)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      folio_number: folio_number,
      hotel_corporate_account: relationship,
      currency: currency
    )

    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      paid_amount: paid_amount,
      outstanding_amount: outstanding_amount,
      currency: currency,
      status: status,
      issued_on: issued_on,
      due_on: due_on
    )
  end
end
