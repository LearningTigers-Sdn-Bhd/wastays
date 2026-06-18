# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Folios::ShowPresenter do
  subject(:presenter) { described_class.new(booking: booking, hotel: hotel) }

  let(:hotel) { create(:hotel, status: "approved") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe King") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      guest_name: "Hanami Saki",
      confirmation_token: "8XXCF4",
      check_in: Time.zone.local(2026, 6, 18, 15, 0, 0),
      check_out: Time.zone.local(2026, 6, 19, 11, 0, 0),
      currency: "MYR"
    )
  end
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, folio_number: 147) }

  before do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "1204")
    folio
  end

  it "uses the folio reference instead of the booking confirmation as the title reference" do
    expect(presenter.folio_reference).to eq(booking.formatted_folio_number)
    expect(presenter.booking_reference).to eq("8XXCF4")
    expect(presenter.header_subtitle).to eq("Booking 8XXCF4 · Hanami Saki · 18 Jun - 19 Jun 2026")
  end

  it "builds split folio details and financial metric items" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "booking_payment", amount: 100)
    create(:folio_forecasted_charge, booking_folio: folio, amount: 100, stay_date: Date.new(2026, 6, 18), charge_kind: "accommodation")

    expect(presenter.folio_detail_rows.map(&:first)).to eq([ "Booking Reference", "Folio Reference", "Guest", "Room", "Stay", "Nights", "Folio Type" ])
    expect(presenter.financial_metric_rows.map(&:first)).to eq([ "Current Balance", "Balance State", "Posted Charges", "Payments/Refunds", "Upcoming Charges", "Upcoming Lines", "Close Readiness" ])
    expect(presenter.financial_metric_rows).to include([ "Payments/Refunds", "MYR 100.00" ])
    expect(presenter.financial_metric_rows).to include([ "Upcoming Lines", "1 pending" ])
  end

  it "labels a zero projected balance as settled" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "booking_payment", amount: 100)
    create(:folio_forecasted_charge, booking_folio: folio, amount: 100, stay_date: Date.new(2026, 6, 18), charge_kind: "accommodation")

    expect(presenter.current_balance).to eq(0.to_d)
    expect(presenter.balance_state_label).to eq("Settled")
    expect(presenter.balance_state_hint).to eq("No amount due")
  end

  it "preserves the sign when showing a credit balance" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 80)

    expect(presenter.current_balance).to eq(-80.to_d)
    expect(presenter.balance_state_label).to eq("Hotel owes guest")
    expect(presenter.primary_summary_items.find { |item| item[:label] == "Balance" }[:value]).to eq("Hotel owes guest · MYR -80.00")
    expect(presenter.mobile_summary_items).to include([ "Balance", "Hotel owes guest · MYR -80.00" ])
  end

  it "builds posted ledger rows with transaction code, credit, and running balance" do
    code = create(:transaction_code, hotel: hotel, code: "PAY", kind: "payment", category: "booking_payment")
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "booking_payment", amount: 100, transaction_code: code, description: "Booking payment")

    row = presenter.posted_rows.first

    expect(row.code).to eq("PAY")
    expect(row.description).to eq("Booking payment")
    expect(row.date_label).to eq("18 Jun")
    expect(row.debit).to eq("—")
    expect(row.credit).to eq("100.00")
    expect(row.balance).to eq("-100.00")
    expect(row.action_label).to eq("⋯")
  end

  it "treats negative refund payments as debit-side balance increases" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -25, description: "Refund")

    row = presenter.posted_rows.first

    expect(row.code).to eq("REFUND")
    expect(row.debit).to eq("25.00")
    expect(row.credit).to eq("—")
    expect(row.balance).to eq("25.00")
  end

  it "labels forecasted rows as pending projected audit postings" do
    create(:folio_forecasted_charge, booking_folio: folio, amount: 66.60, stay_date: Date.new(2026, 6, 18), charge_kind: "tax", description: "Tax: Service Charge - 2026-06-18")

    row = presenter.forecasted_rows.first

    expect(row.code).to eq("SVC")
    expect(row.description).to eq("Tax: Service Charge - 2026-06-18")
    expect(row.date_label).to eq("18 Jun")
    expect(row.detail_label).to eq("Tax linked to ROOM")
    expect(row.source_label).to eq("Upcoming")
    expect(row.tax).to eq("66.60")
    expect(row.balance).to eq("Pending")
    expect(presenter.forecasted_section_summary).to include("Will post by audit")
    expect(presenter.forecasted_section_summary).to include("upcoming")
  end

  it "shows close folio as not ready when forecasts remain" do
    create(:folio_forecasted_charge, booking_folio: folio, amount: 100, stay_date: Date.new(2026, 6, 18), charge_kind: "accommodation")

    expect(presenter.close_folio_ready?).to be(false)
    expect(presenter.close_folio_status_text).to eq("Close Folio: Not ready · 1 forecasted charge will post by night audit")
  end

  it "shows close folio as a ready placeholder when settled and no forecasts remain" do
    expect(presenter.close_folio_ready?).to be(true)
    expect(presenter.close_folio_label).to eq("Ready")
    expect(presenter.close_folio_hint).to eq("Ready to close")
  end

  it "keeps reversed originals visible while the reversal row brings running balance back down" do
    original = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100, description: "Wrong charge")
    reversal = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction", amount: -100, description: "Reversal", reversal_of_transaction: original)
    original.update!(voided_by_transaction: reversal)

    rows = presenter.posted_rows

    expect(rows.first.reversed).to be(true)
    expect(rows.first.balance).to eq("100.00")
    expect(rows.second.balance).to eq("0.00")
  end
end
