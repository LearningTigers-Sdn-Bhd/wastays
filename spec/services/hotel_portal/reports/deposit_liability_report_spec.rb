# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DepositLiabilityReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:as_of_date) { Date.new(2026, 5, 20) }

  describe "#call" do
    it "reports explicit booking payments that remain unearned" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 3.days, check_out: as_of_date + 5.days, guest_name: "Future Guest", confirmation_token: "WS-FUTURE")
      folio = create(:booking_folio, booking: booking, hotel: hotel, folio_number: "F-100")
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 300, posting_date: as_of_date - 1.day)

      result = described_class.new(hotel: hotel, as_of_date: as_of_date).call

      expect(result.rows.size).to eq(1)
      expect(result.rows.first).to include(
        guest_name: "Future Guest",
        confirmation_token: "WS-FUTURE",
        booking_payment_amount: 300.to_d,
        earned_amount: 0.to_d,
        refund_amount: 0.to_d,
        remaining_liability: 300.to_d
      )
      expect(result.totals[:remaining_liability]).to eq(300.to_d)
    end

    it "reduces liability by earned charges and refunds" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: as_of_date - 1.day, check_out: as_of_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 330, posting_date: as_of_date - 2.days)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100, posting_date: as_of_date - 1.day)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "tax", amount: 10, posting_date: as_of_date - 1.day)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "refund", amount: -50, posting_date: as_of_date)

      row = described_class.new(hotel: hotel, as_of_date: as_of_date).call.rows.first

      expect(row[:booking_payment_amount]).to eq(330.to_d)
      expect(row[:earned_amount]).to eq(110.to_d)
      expect(row[:refund_amount]).to eq(50.to_d)
      expect(row[:remaining_liability]).to eq(170.to_d)
    end

    it "uses adjustments in the earned amount" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: as_of_date - 1.day, check_out: as_of_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 250, posting_date: as_of_date - 2.days)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100, posting_date: as_of_date - 1.day)
      create(:folio_transaction, booking_folio: folio, transaction_type: :adjustment, category: "discount", amount: -20, posting_date: as_of_date)

      row = described_class.new(hotel: hotel, as_of_date: as_of_date).call.rows.first

      expect(row[:earned_amount]).to eq(80.to_d)
      expect(row[:remaining_liability]).to eq(170.to_d)
    end

    it "excludes fully earned deposits" do
      booking = create(:booking, hotel: hotel, status: "completed", check_in: as_of_date - 2.days, check_out: as_of_date)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 100, posting_date: as_of_date - 3.days)
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100, posting_date: as_of_date - 2.days)

      result = described_class.new(hotel: hotel, as_of_date: as_of_date).call

      expect(result.rows).to be_empty
      expect(result.totals[:remaining_liability]).to eq(0.to_d)
    end

    it "ignores non-advance-deposit payments" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "gateway_payment", amount: 300, posting_date: as_of_date - 1.day)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100, posting_date: as_of_date - 1.day)

      result = described_class.new(hotel: hotel, as_of_date: as_of_date).call

      expect(result.rows).to be_empty
    end

    it "ignores future-dated booking payments" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 2.days, check_out: as_of_date + 3.days)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 300, posting_date: as_of_date + 1.day)

      result = described_class.new(hotel: hotel, as_of_date: as_of_date).call

      expect(result.rows).to be_empty
    end

    it "excludes transactions after the as-of date and other hotels" do
      included = create(:booking, hotel: hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Included Guest")
      included_folio = create(:booking_folio, booking: included, hotel: hotel)
      create(:folio_transaction, booking_folio: included_folio, transaction_type: :payment, category: "booking_payment", amount: 100, posting_date: as_of_date)
      create(:folio_transaction, booking_folio: included_folio, transaction_type: :charge, category: "accommodation", amount: 90, posting_date: as_of_date + 1.day)

      other_booking = create(:booking, hotel: other_hotel, status: "confirmed", check_in: as_of_date + 1.day, check_out: as_of_date + 2.days, guest_name: "Other Hotel Guest")
      other_folio = create(:booking_folio, booking: other_booking, hotel: other_hotel)
      create(:folio_transaction, booking_folio: other_folio, transaction_type: :payment, category: "booking_payment", amount: 500, posting_date: as_of_date)

      result = described_class.new(hotel: hotel, as_of_date: as_of_date).call

      expect(result.rows.size).to eq(1)
      expect(result.rows.first[:guest_name]).to eq("Included Guest")
      expect(result.rows.first[:remaining_liability]).to eq(100.to_d)
    end

    it "includes unapplied booking and group deposits of both kinds" do
      booking = create(:booking, hotel: hotel, check_in: as_of_date + 1.day, check_out: as_of_date + 2.days)
      group = create(:group_booking, hotel: hotel, default_check_in: as_of_date + 1.day, default_check_out: as_of_date + 2.days)
      create(:deposit, booking: booking, hotel: hotel, amount: 75, received_at: as_of_date.noon)
      create(:deposit, :prepayment, :group_owned, group_booking: group, hotel: hotel, amount: 125,
        currency: hotel.default_currency, received_at: as_of_date.noon)

      result = described_class.new(hotel: hotel, as_of_date: as_of_date).call

      expect(result.rows.map { |row| row[:folio_number] }).to contain_exactly("Unapplied Security", "Unapplied Prepayment")
      expect(result.totals[:remaining_liability]).to eq(200.to_d)
    end

    it "does not double count a partially applied unified deposit" do
      report_date = hotel.current_business_date
      booking = create(:booking, hotel: hotel, total_amount: 100, check_in: report_date + 1.day, check_out: report_date + 2.days)
      folio = create(:booking_folio, booking: booking, hotel: hotel, currency: booking.currency)
      deposit = create(:deposit, :prepayment, booking: booking, hotel: hotel, amount: 100,
        currency: booking.currency, received_at: Time.current)
      application = Deposits::Apply.call(deposit: deposit, booking_folio: folio, amount: 40, posting_date: report_date)
      expect(application).to be_success

      result = described_class.new(hotel: hotel, as_of_date: report_date).call

      expect(result.rows.map { |row| row[:remaining_liability] }).to contain_exactly(40.to_d, 60.to_d)
      expect(result.totals[:remaining_liability]).to eq(100.to_d)
    end
  end
end
