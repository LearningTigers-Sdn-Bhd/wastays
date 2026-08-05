# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cancellations::Quote do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:arrival) { Date.current + 10.days }
  # 3 nights, MYR 300 pre-tax room revenue (MYR 100 a night).
  let(:booking) do
    create(:booking, hotel: hotel, check_in: arrival, check_out: arrival + 3.days,
      total_amount: 360.0, tourism_tax_amount: 30.0)
  end
  let(:policy) { hotel.hotel_reservation_policies.find_by(policy_type: "cancellation") }

  before do
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 300.0)
    ReservationPolicies::EnsureDefaults.call(hotel)
  end

  def tier(days, rate, pricing_type: "percentage", basis: "total_stay")
    policy.cancellation_tiers.create!(
      days_before_arrival: days, pricing_type: pricing_type, rate_value: rate,
      percentage_basis: (basis if pricing_type == "percentage"), position: days
    )
  end

  def quote(business_date: Date.current) = described_class.call(booking: booking, business_date: business_date)

  it "charges nothing while the policy is inactive" do
    result = quote

    expect(result).to be_success
    expect(result.fee_amount).to eq(0)
  end

  context "with a tiered policy" do
    before do
      policy.update!(active: true, refund_processing_days: 7, refund_method: "original_payment_method")
      tier(14, 0)
      tier(7, 50)
      tier(0, 1, pricing_type: "nights")
    end

    it "picks the tightest band the guest still qualifies for" do
      # 10 days out clears the 7-day band but not the 14-day one.
      expect(quote.fee_amount).to eq(150.0)
      expect(quote.tier.days_before_arrival).to eq(7)
    end

    it "charges nothing inside the free-cancellation band" do
      expect(quote(business_date: arrival - 20.days).fee_amount).to eq(0)
    end

    it "treats a threshold as inclusive on its exact day" do
      expect(quote(business_date: arrival - 14.days).fee_amount).to eq(0)
      expect(quote(business_date: arrival - 13.days).fee_amount).to eq(150.0)
    end

    it "falls to the tightest band on the day of arrival" do
      expect(quote(business_date: arrival).fee_amount).to eq(100.0)
      expect(quote(business_date: arrival).tier.days_before_arrival).to eq(0)
    end

    it "counts days from the hotel's business date, not the wall clock" do
      expect(quote(business_date: arrival - 7.days).days_out).to eq(7)
    end
  end

  describe "the refund is derived from the fee, never stored" do
    before do
      policy.update!(active: true)
      tier(0, 50)
    end

    it "returns the balance of what the guest paid" do
      create(:deposit, hotel: hotel, booking: booking, amount: 200.0, status: "held")

      result = quote

      expect(result.fee_amount).to eq(150.0)
      expect(result.amount_paid).to eq(200.0)
      expect(result.refund_amount).to eq(50.0)
    end

    it "never returns a negative refund when the fee exceeds what was paid" do
      create(:deposit, hotel: hotel, booking: booking, amount: 50.0, status: "held")

      result = quote

      expect(result.fee_amount).to eq(150.0)
      expect(result.refund_amount).to eq(0)
    end

    it "refunds nothing when the guest paid nothing" do
      expect(quote.refund_amount).to eq(0)
    end

    it "ignores deposits the hotel no longer holds" do
      create(:deposit, hotel: hotel, booking: booking, amount: 200.0, status: "refunded")

      expect(quote.amount_paid).to eq(0)
    end
  end

  describe "fee shapes" do
    before { policy.update!(active: true) }

    it "keeps whole nights" do
      tier(0, 2, pricing_type: "nights")

      expect(quote.fee_amount).to eq(200.0)
    end

    it "keeps a fixed sum" do
      tier(0, 75, pricing_type: "fixed")

      expect(quote.fee_amount).to eq(75.0)
    end

    it "keeps a share of the first night" do
      tier(0, 50, basis: "first_night")

      expect(quote.fee_amount).to eq(50.0)
    end

    # Pre-tax: the fee posts under CANCEL and picks up ROOM's tax rules on the way
    # to the folio, so quoting the gross total would tax it twice.
    it "works from pre-tax room revenue, not the booking's gross total" do
      tier(0, 100)

      expect(quote.fee_amount).to eq(300.0)
      expect(quote.fee_amount).not_to eq(booking.total_amount)
    end
  end

  it "falls back to the policy's own pricing when no tier matches" do
    policy.update!(active: true, pricing_type: "fixed", rate_value: 25)
    tier(30, 10, pricing_type: "fixed")

    result = quote

    expect(result.tier).to be_nil
    expect(result.fee_amount).to eq(25.0)
  end

  it "charges nothing when no tier matches and the policy is manual" do
    policy.update!(active: true)
    tier(30, 10, pricing_type: "fixed")

    expect(quote.fee_amount).to eq(0)
  end
end
