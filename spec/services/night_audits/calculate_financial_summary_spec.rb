# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::CalculateFinancialSummary, type: :service do
  let(:hotel) { create(:hotel) }
  let(:business_date) { 1.day.ago.to_date }

  it "calculates correct financial totals for a business date based on posting_date" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)

    # Accommodation charge for the date
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100.0,
      posting_date: business_date
    )

    # Tax charge for the date
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 10.0,
      posting_date: business_date
    )

    # Payment for the business date
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 110.0,
      posting_date: business_date
    )

    # Payment for DIFFERENT business date (should not be included)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 50.0,
      posting_date: business_date + 1.day
    )

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result[:room_revenue]).to eq(100.0)
    expect(result[:tax_revenue]).to eq(10.0)
    expect(result[:payments_total]).to eq(110.0)
    expect(result[:no_show_charges]).to eq(0.0)
  end

  it "ignores created_at window and uses posting_date" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)
    window = hotel.business_day_window_for(business_date)

    # Posted to business_date but created OUTSIDE window
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 100.0,
      posting_date: business_date,
      created_at: window.end + 1.hour
    )

    # Posted to NEXT business_date but created INSIDE window
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 50.0,
      posting_date: business_date + 1.day,
      created_at: window.begin + 1.hour
    )

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result[:payments_total]).to eq(100.0)
  end

  it "identifies no-show charges correctly" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)

    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "no_show_charge",
      amount: 50.0,
      posting_date: business_date
    )

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result[:no_show_charges]).to eq(50.0)
    expect(result[:room_revenue]).to eq(0.0)
  end

  it "uses category as the no-show accounting source of truth" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)

    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100.0,
      posting_date: business_date
    )
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "no_show_charge",
      amount: 50.0,
      posting_date: business_date
    )
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 5.0,
      posting_date: business_date
    )

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result[:room_revenue]).to eq(100.0)
    expect(result[:tax_revenue]).to eq(5.0)
    expect(result[:no_show_charges]).to eq(50.0)
  end
end
