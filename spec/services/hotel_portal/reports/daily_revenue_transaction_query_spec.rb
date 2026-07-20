# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueTransactionQuery do
  let(:hotel) { create(:hotel) }
  let(:filters) { {} }

  subject(:query) do
    described_class.new(
      hotel: hotel,
      start_date: Date.new(2026, 7, 16),
      end_date: Date.new(2026, 7, 17),
      filters: filters
    )
  end

  def create_transaction(hotel:, **attrs)
    booking = attrs.delete(:booking) || create(:booking, hotel: hotel)
    folio = attrs.delete(:folio) || create(:booking_folio, booking: booking, hotel: hotel)
    attrs[:posting_date] ||= Date.new(2026, 7, 16)
    create(:folio_transaction, booking_folio: folio, **attrs)
  end

  it "scopes by hotel and posting date and orders newest activity first" do
    older = create_transaction(hotel: hotel, posting_date: Date.new(2026, 7, 16), posted_at: Time.zone.local(2026, 7, 16, 8))
    newer = create_transaction(hotel: hotel, posting_date: Date.new(2026, 7, 17), posted_at: Time.zone.local(2026, 7, 17, 9))
    create_transaction(hotel: create(:hotel), posting_date: newer.posting_date)
    create_transaction(hotel: hotel, posting_date: Date.new(2026, 7, 15))

    expect(query.call.ids).to eq([ newer.id, older.id ])
  end

  it "searches transaction and booking identity fields" do
    booking = create(:booking, hotel: hotel, guest_name: "Charter Guest")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    match = create_transaction(hotel: hotel, booking: booking, folio: folio, description: "Sunset charter")
    create_transaction(hotel: hotel, description: "Room charge")

    filters[:q] = "charter"

    expect(query.call.ids).to eq([ match.id ])
  end

  it "filters reversals without hiding either ledger entry by default" do
    original = create_transaction(hotel: hotel)
    reversal = create_transaction(
      hotel: hotel,
      booking: original.booking_folio.booking,
      folio: original.booking_folio,
      transaction_type: "adjustment",
      category: "correction",
      amount: -original.amount,
      posting_date: original.posting_date,
      reversal_of_transaction: original
    )
    original.update_column(:voided_by_transaction_id, reversal.id)

    result = described_class.new(
      hotel: hotel,
      start_date: original.posting_date,
      end_date: original.posting_date,
      filters: {}
    ).call

    expect(result.ids).to contain_exactly(original.id, reversal.id)
  end

  it "filters by reversal status" do
    original = create_transaction(hotel: hotel)
    reversal = create_transaction(
      hotel: hotel,
      booking: original.booking_folio.booking,
      folio: original.booking_folio,
      transaction_type: "adjustment",
      category: "correction",
      amount: -original.amount,
      posting_date: original.posting_date,
      reversal_of_transaction: original
    )
    original.update_column(:voided_by_transaction_id, reversal.id)
    untouched = create_transaction(hotel: hotel, posting_date: original.posting_date)

    scoped = described_class.new(
      hotel: hotel,
      start_date: original.posting_date,
      end_date: original.posting_date,
      filters: { reversal_status: "original" }
    ).call

    expect(scoped.ids).to contain_exactly(untouched.id)
  end

  it "filters by transaction type and category" do
    charge = create_transaction(hotel: hotel, transaction_type: "charge", category: "accommodation")
    create_transaction(hotel: hotel, transaction_type: "payment", category: "cash")

    filters[:transaction_type] = "charge"
    filters[:category] = "accommodation"

    expect(query.call.ids).to eq([ charge.id ])
  end

  it "does not grow query count with more rows once eager loaded" do
    def sql_count
      count = 0
      callback = lambda do |_name, _started, _finished, _id, payload|
        next if payload[:cached]
        next if payload[:name].in?([ "SCHEMA", "TRANSACTION" ])

        count += 1
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end

    def materialize(scope)
      scope.each do |transaction|
        row = HotelPortal::Reports::DailyRevenueTransactionRow.new(transaction)
        [ row.transaction_code, row.service_name, row.booking_reference, row.folio_number, row.guest_name, row.room_number, row.actor_name ]
      end
    end

    10.times { create_transaction(hotel: hotel) }
    small_count = sql_count { materialize(query.call) }

    described_class.new(hotel: hotel, start_date: Date.new(2026, 7, 16), end_date: Date.new(2026, 7, 17), filters: {})
    20.times { create_transaction(hotel: hotel) }
    large_query = described_class.new(hotel: hotel, start_date: Date.new(2026, 7, 16), end_date: Date.new(2026, 7, 17), filters: {})
    large_count = sql_count { materialize(large_query.call) }

    expect(large_count).to be <= small_count + 1
  end
end
