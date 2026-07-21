# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueCellDetail do
  let(:hotel) { create(:hotel) }
  let(:date) { Date.new(2026, 5, 6) }

  it "returns the folio transactions backing a charge category on a given date" do
    booking = create(:booking, hotel: hotel, source: "walk_in")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: date)
    create(:folio_transaction, booking_folio: folio, category: "tax", amount: 10, posting_date: date)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 999, posting_date: date - 1.day)

    detail = described_class.new(hotel: hotel, start_date: date, end_date: date, category: "accommodation").call

    expect(detail.category_label).to eq("Accommodation")
    expect(detail.entries.size).to eq(1)
    expect(detail.entries.first.amount).to eq(100.to_d)
    expect(detail.entries.first.booking_reference).to eq(booking.confirmation_token)
  end

  it "excludes transactions from other hotels" do
    other_hotel = create(:hotel)
    booking = create(:booking, hotel: other_hotel)
    folio = create(:booking_folio, booking: booking, hotel: other_hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 500, posting_date: date)

    detail = described_class.new(hotel: hotel, start_date: date, end_date: date, category: "accommodation").call

    expect(detail.entries).to be_empty
  end

  it "buckets agent vs corporate bank transfers into separate categories" do
    agent_account = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
    corporate_account = create(:hotel_corporate_account, hotel: hotel, account_type: "company")
    create(:ar_payment, hotel: hotel, hotel_corporate_account: agent_account, payment_method: "bank_transfer", amount: 400, received_at: date)
    create(:ar_payment, hotel: hotel, hotel_corporate_account: corporate_account, payment_method: "bank_transfer", amount: 250, received_at: date)

    agent_detail = described_class.new(hotel: hotel, start_date: date, end_date: date, category: "agent_bank_transfer").call
    corporate_detail = described_class.new(hotel: hotel, start_date: date, end_date: date, category: "corporate_bank_transfer").call

    expect(agent_detail.entries.map(&:amount)).to eq([ 400.to_d ])
    expect(agent_detail.entries.first.source_label).to eq(agent_account.corporate_account.name)
    expect(corporate_detail.entries.map(&:amount)).to eq([ 250.to_d ])
  end

  it "returns no entries for an unrecognized category" do
    detail = described_class.new(hotel: hotel, start_date: date, end_date: date, category: "not_a_real_category").call

    expect(detail.entries).to be_empty
  end
end
