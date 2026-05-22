# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::CalculateBusinessDayFinancials, type: :service do
  let(:hotel) { create(:hotel) }
  let(:business_date) { 1.day.ago.to_date }

  it "calculates correct financial totals for a business date" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)

    # Accommodation charge for the date
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100.0,
      metadata: { stay_date: business_date.iso8601 }
    )

    # Tax charge for the date
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 10.0,
      metadata: { stay_date: business_date.iso8601 }
    )

    # Payment within the business window
    window = hotel.business_day_window_for(business_date)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 110.0,
      created_at: window.begin + 1.hour
    )

    # Payment OUTSIDE the business window (should not be included)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 50.0,
      created_at: window.end + 1.hour
    )

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result[:room_revenue]).to eq(100.0)
    expect(result[:tax_revenue]).to eq(10.0)
    expect(result[:payments_total]).to eq(110.0)
    expect(result[:no_show_charges]).to eq(0.0)
  end

  it "identifies no-show charges correctly" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)

    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "no_show_charge",
      amount: 50.0,
      metadata: { stay_date: business_date.iso8601 }
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
      metadata: { stay_date: business_date.iso8601 }
    )
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "no_show_charge",
      amount: 50.0,
      metadata: { stay_date: business_date.iso8601, posting_source: "no_show" }
    )
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 5.0,
      metadata: { stay_date: business_date.iso8601, posting_source: "no_show" }
    )

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result[:room_revenue]).to eq(100.0)
    expect(result[:tax_revenue]).to eq(5.0)
    expect(result[:no_show_charges]).to eq(50.0)
  end
end
