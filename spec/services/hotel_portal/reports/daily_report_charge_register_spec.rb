# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyReportChargeRegister do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:date) { Date.new(2026, 7, 21) }
  let(:room_code) { hotel.transaction_codes.find_by!(system_key: "room_revenue") }
  let(:sst_code) { hotel.transaction_codes.find_by!(system_key: "sst_tax") }

  before do
    room_code.update!(active: true, is_taxable: true)
    sst_code.update!(active: true)
    room_code.transaction_code_taxes.find_or_create_by!(primary_tax_key: "sst_tax")
  end

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

  def create_legacy_pairs(count)
    Array.new(count) do
      pair_booking = create(:booking, hotel: hotel)
      pair_folio = create(:booking_folio, booking: pair_booking, hotel: hotel)
      charge = create(:folio_transaction, booking_folio: pair_folio, transaction_code: room_code,
        category: "accommodation", amount: 480, posting_date: date)
      tax = create(:folio_transaction, booking_folio: pair_folio, transaction_code: sst_code,
        category: "tax", amount: 38.40, posting_date: date)
      [ charge.id, tax.id ]
    end.flatten
  end

  def preloaded_transactions(ids)
    FolioTransaction.where(id: ids).includes(:transaction_code, booking_folio: :booking).to_a
  end

  it "absorbs directly linked taxes into their parent charge" do
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date,
      metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

    result = described_class.new(transactions: [ sst, charge ]).call

    expect(result.rows.one?).to be(true)
    expect(result.rows.first).to have_attributes(signed_amount: 480.to_d, tax_amount: 38.40.to_d)
    expect(result.rows.first.transaction_ids).to eq([ charge.id ])
    expect(result.rows.first.tax_transaction_ids).to eq([ sst.id ])
    expect(result).to have_attributes(amount_total: 480.to_d, tax_total: 38.40.to_d)
  end

  it "deduplicates a repeated directly linked tax transaction" do
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date,
      metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })

    row = described_class.new(transactions: [ sst, sst, charge ]).call.rows.sole

    expect(row).to have_attributes(tax_amount: 38.40.to_d, tax_transaction_ids: [ sst.id ])
  end

  it "matches nightly tax by booking, stay date, and source transaction code" do
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date,
      metadata: { stay_date: date.iso8601 })
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date,
      metadata: {
        stay_date: date.iso8601,
        tax_line: { type: "sst", source_transaction_code_id: room_code.id }
      })

    row = described_class.new(transactions: [ sst, charge ]).call.rows.sole

    expect(row.tax_amount).to eq(38.40.to_d)
    expect(row.tax_transaction_ids).to eq([ sst.id ])
  end

  it "does not infer tax with an unavailable explicit parent" do
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date,
      metadata: { stay_date: date.iso8601 })
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date,
      metadata: {
        parent_folio_transaction_id: charge.id + 10_000,
        stay_date: date.iso8601,
        tax_line: { type: "sst", source_transaction_code_id: room_code.id }
      })

    result = described_class.new(transactions: [ sst, charge ]).call

    expect(result.rows.sole).to have_attributes(tax_amount: 0.to_d, tax_transaction_ids: [])
    expect(result.tax_total).to eq(0.to_d)
  end

  it "matches legacy tax by the configured tax rule when source metadata is absent" do
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date)

    row = described_class.new(transactions: [ sst, charge ]).call.rows.sole

    expect(row.tax_amount).to eq(38.40.to_d)
    expect(row.tax_transaction_ids).to eq([ sst.id ])
  end

  it "honors booking tax inclusion overrides without relying on fallback matching" do
    parking_code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")
    room_code.update!(is_taxable: false)
    parking_code.update!(is_taxable: false)
    parking_code.transaction_code_taxes.destroy_all
    create(:booking_tax_inclusion_override, hotel: hotel, booking: booking,
      transaction_code: room_code, primary_tax_key: "sst_tax", action: "exclude")
    create(:booking_tax_inclusion_override, hotel: hotel, booking: booking,
      transaction_code: parking_code, primary_tax_key: "sst_tax", action: "include")
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    parking_charge = create(:folio_transaction, booking_folio: folio, transaction_code: parking_code,
      category: "parking", amount: 20, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date)

    result = described_class.new(transactions: [ sst, room_charge, parking_charge ]).call
    room_row = result.rows.find { |row| row.transaction_ids.include?(room_charge.id) }
    parking_row = result.rows.find { |row| row.transaction_ids.include?(parking_charge.id) }

    expect(room_row.tax_amount).to eq(0.to_d)
    expect(parking_row).to have_attributes(tax_amount: 38.40.to_d, tax_transaction_ids: [ sst.id ])
  end

  it "does not create a missing transaction code for an enabled custom rule" do
    custom_tax = create(:hotel_tax, hotel: hotel, name: "Heritage Fee", code: "HERITAGE", enabled: true)
    custom_code = custom_tax.transaction_code
    custom_tax.update_column(:transaction_code_id, nil)
    custom_code.destroy!
    room_code.transaction_code_taxes.destroy_all
    room_code.transaction_code_taxes.create!(hotel_tax: custom_tax)
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date)
    transaction_code_count = TransactionCode.count

    described_class.new(transactions: [ sst, charge ]).call

    expect(TransactionCode.count).to eq(transaction_code_count)
    expect(custom_tax.reload.transaction_code_id).to be_nil
  end

  it "maps an enabled custom rule to its existing transaction code" do
    custom_tax = create(:hotel_tax, hotel: hotel, name: "Heritage Fee", code: "HERITAGE", enabled: true)
    custom_code = custom_tax.transaction_code
    room_code.transaction_code_taxes.destroy_all
    room_code.transaction_code_taxes.create!(hotel_tax: custom_tax)
    room_code.update!(is_taxable: false)
    parking_code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")
    parking_code.transaction_code_taxes.destroy_all
    parking_code.update!(is_taxable: false)
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    parking_charge = create(:folio_transaction, booking_folio: folio, transaction_code: parking_code,
      category: "parking", amount: 20, posting_date: date)
    custom_tax_transaction = create(:folio_transaction, booking_folio: folio, transaction_code: custom_code,
      category: "tax", amount: 2, posting_date: date)

    result = described_class.new(transactions: [ custom_tax_transaction, room_charge, parking_charge ]).call
    room_row = result.rows.find { |row| row.transaction_ids.include?(room_charge.id) }
    parking_row = result.rows.find { |row| row.transaction_ids.include?(parking_charge.id) }

    expect(room_row).to have_attributes(tax_amount: 2.to_d, tax_transaction_ids: [ custom_tax_transaction.id ])
    expect(parking_row).to have_attributes(tax_amount: 0.to_d, tax_transaction_ids: [])
  end

  it "keeps SQL query count bounded as booking and code pairs grow" do
    small_transactions = preloaded_transactions(create_legacy_pairs(2))
    small_count = sql_count { described_class.new(transactions: small_transactions).call }
    large_transactions = preloaded_transactions(create_legacy_pairs(8))
    large_count = sql_count { described_class.new(transactions: large_transactions).call }

    expect(large_count).to be <= small_count + 1
  end

  it "falls back to the sole booking and date group for legacy tax when the current tax rule differs" do
    room_code.transaction_code_taxes.destroy_all
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    hotel.update!(tourism_tax_enabled: true)
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date)

    row = described_class.new(transactions: [ sst, charge ]).call.rows.sole

    expect(row.tax_amount).to eq(38.40.to_d)
    expect(row.tax_transaction_ids).to eq([ sst.id ])
  end

  it "does not fall back when legacy tax has multiple booking and date groups" do
    room_code.transaction_code_taxes.destroy_all
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    room_code.update!(is_taxable: false)
    hotel.update!(tourism_tax_enabled: true)
    parking_code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")
    parking_code.transaction_code_taxes.destroy_all
    parking_code.update!(is_taxable: false)
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    parking_charge = create(:folio_transaction, booking_folio: folio, transaction_code: parking_code,
      category: "parking", amount: 20, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date)

    result = described_class.new(transactions: [ sst, room_charge, parking_charge ]).call

    expect(result.rows).to all(have_attributes(tax_amount: 0.to_d, tax_transaction_ids: []))
    expect(result.tax_total).to eq(0.to_d)
  end

  it "falls back to the sole taxable group when legacy tax has multiple booking and date groups" do
    room_code.transaction_code_taxes.destroy_all
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    room_code.update!(is_taxable: true)
    hotel.update!(tourism_tax_enabled: true)
    parking_code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")
    parking_code.transaction_code_taxes.destroy_all
    parking_code.update!(is_taxable: false)
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 720, posting_date: date)
    parking_charge = create(:folio_transaction, booking_folio: folio, transaction_code: parking_code,
      category: "parking", amount: 150, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 43.20, posting_date: date, description: "SST 6%")

    result = described_class.new(transactions: [ sst, room_charge, parking_charge ]).call
    room_row = result.rows.find { |row| row.transaction_ids.include?(room_charge.id) }
    parking_row = result.rows.find { |row| row.transaction_ids.include?(parking_charge.id) }

    expect(room_row).to have_attributes(tax_amount: 43.20.to_d, tax_transaction_ids: [ sst.id ])
    expect(parking_row).to have_attributes(tax_amount: 0.to_d, tax_transaction_ids: [])
    expect(result.tax_total).to eq(43.20.to_d)
  end

  it "does not fall back when multiple legacy charge groups are taxable" do
    room_code.transaction_code_taxes.destroy_all
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    room_code.update!(is_taxable: true)
    hotel.update!(tourism_tax_enabled: true)
    parking_code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")
    parking_code.transaction_code_taxes.destroy_all
    parking_code.update!(is_taxable: true)
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 720, posting_date: date)
    parking_charge = create(:folio_transaction, booking_folio: folio, transaction_code: parking_code,
      category: "parking", amount: 150, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 43.20, posting_date: date, description: "SST 6%")

    result = described_class.new(transactions: [ sst, room_charge, parking_charge ]).call

    expect(result.rows).to all(have_attributes(tax_amount: 0.to_d, tax_transaction_ids: []))
    expect(result.tax_total).to eq(0.to_d)
  end

  it "groups same-service booking charges and never duplicates combined taxes" do
    first = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 240, posting_date: date,
      metadata: { stay_date: date.iso8601 })
    second = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 240, posting_date: date,
      metadata: { stay_date: date.iso8601 })
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date,
      metadata: {
        stay_date: date.iso8601,
        tax_line: { type: "sst", source_transaction_code_id: room_code.id }
      })

    result = described_class.new(transactions: [ sst, second, first ]).call

    expect(result.rows.one?).to be(true)
    expect(result.rows.first.signed_amount).to eq(480.to_d)
    expect(result.rows.first.tax_amount).to eq(38.40.to_d)
    expect(result.rows.first.transaction_ids).to contain_exactly(first.id, second.id)
    expect(result.rows.first.tax_transaction_ids).to eq([ sst.id ])
  end

  it "sums multiple tax types and keeps adjustments as zero-tax rows" do
    charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: date)
    sst = create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: date,
      metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "sst" } })
    tourism = create(:folio_transaction, booking_folio: folio, transaction_code: hotel.transaction_codes.find_by!(system_key: "tourism_tax"),
      category: "tax", amount: 10, posting_date: date,
      metadata: { parent_folio_transaction_id: charge.id, tax_line: { type: "tourism_tax" } })
    adjustment = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment",
      category: "discount", amount: -20, posting_date: date)

    result = described_class.new(transactions: [ tourism, adjustment, sst, charge ]).call
    charge_row = result.rows.find { |row| row.transaction_ids.include?(charge.id) }
    adjustment_row = result.rows.find { |row| row.transaction_ids.include?(adjustment.id) }

    expect(charge_row.tax_amount).to eq(48.40.to_d)
    expect(adjustment_row).to have_attributes(signed_amount: -20.to_d, tax_amount: 0.to_d)
    expect(result).to have_attributes(amount_total: 460.to_d, tax_total: 48.40.to_d)
  end
end
