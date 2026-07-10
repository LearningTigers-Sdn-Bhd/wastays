# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ManagersFlashReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  describe "#call" do
    it "aggregates both occupancy and posted revenue metrics correctly" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create(:room_inventory, room_type: room_type, date: start_date, quantity: 8, status: "open")
      create(:room_inventory, room_type: room_type, date: end_date, quantity: 10, status: "open")

      # Occupancy part: Booking spanning 2 days
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 2.days)
      create_list(:booking_room, 2, booking: booking, room_type: room_type, subtotal: 200) # 200 per day

      # Posted Revenue part: Folio transactions on start_date
      folio = create(:booking_folio, booking: booking)
      create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 200, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "tax", amount: 20, posting_date: start_date)

      # Adjustment on end_date
      tx_to_adjust = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: end_date)
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: "adjustment",
        category: "adjustment",
        amount: -50,
        posting_date: end_date,
        reversal_of_transaction: tx_to_adjust
      )

      # Transactions for other hotel (should be excluded)
      other_booking = create(:booking, hotel: other_hotel, status: "confirmed", check_in: start_date, check_out: start_date + 2.days)
      other_folio = create(:booking_folio, booking: other_booking)
      create(:folio_transaction, booking_folio: other_folio, category: "accommodation", amount: 500, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(2)

      # Day 1 (start_date)
      day1 = result.rows[0]
      expect(day1[:date]).to eq(start_date)
      expect(day1[:rooms_sold]).to eq(2)
      expect(day1[:rooms_available]).to eq(8)
      expect(day1[:occupancy_rate]).to eq(0.25)
      expect(day1[:adr]).to eq(100.to_d) # 200 revenue / 2 rooms
      expect(day1[:revpar]).to eq(25.to_d) # 200 revenue / 8 available
      expect(day1[:room_revenue]).to eq(200.to_d) # Posted tx
      expect(day1[:tax_amount]).to eq(20.to_d)
      expect(day1[:total_revenue]).to eq(220.to_d)

      # Day 2 (end_date)
      day2 = result.rows[1]
      expect(day2[:date]).to eq(end_date)
      expect(day2[:rooms_sold]).to eq(2)
      expect(day2[:rooms_available]).to eq(10)
      expect(day2[:room_revenue]).to eq(50.to_d) # 100 - 50 adjustment
      expect(day2[:total_revenue]).to eq(50.to_d)

      # Totals
      expect(result.totals[:rooms_sold]).to eq(4)
      expect(result.totals[:rooms_available]).to eq(18)
      expect(result.totals[:room_revenue]).to eq(250.to_d)
      expect(result.totals[:tax_amount]).to eq(20.to_d)
      expect(result.totals[:total_revenue]).to eq(270.to_d)
      expect(result.totals[:adr]).to eq(100.to_d) # 400 total booking rev / 4 rooms sold
    end

    it "handles zero availability and zero sales gracefully" do
      create(:room_type, hotel: hotel, quantity: 0)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: start_date).call

      expect(result.rows.first[:occupancy_rate]).to eq(0)
      expect(result.rows.first[:adr]).to eq(0)
      expect(result.rows.first[:revpar]).to eq(0)
    end
  end
end
