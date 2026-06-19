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

    expect(presenter.folio_detail_rows.map(&:first)).to eq([ "Booking Reference", "Folio Reference", "Guest", "Room", "Stay / Nights", "Folio Type" ])
    expect(presenter.folio_detail_rows).to include([ "Stay / Nights", "18 Jun 2026 - 19 Jun 2026 / 1 Night" ])
    expect(presenter.financial_metric_rows.map(&:first)).to eq([ "Current Balance", "Balance State", "Posted Charges", "Payments / Refunds", "Upcoming Charges", "Checkout Readiness" ])
    expect(presenter.financial_metric_rows).to include([ "Payments / Refunds", "MYR 100.00" ])
    expect(presenter.financial_metric_rows).to include([ "Checkout Readiness", "Not ready" ])
  end

  it "formats multi-night stays with full dates and pluralized nights" do
    booking.update!(check_in: Time.zone.local(2026, 6, 11, 15, 0, 0), check_out: Time.zone.local(2026, 6, 13, 11, 0, 0))

    expect(presenter.formatted_stay_nights).to eq("11 Jun 2026 - 13 Jun 2026 / 2 Nights")
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
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "booking_payment", amount: 100, transaction_code: code, description: "Booking payment", posting_date: booking.check_in.to_date)

    row = presenter.posted_rows.first

    expect(row.code).to eq("PAY")
    expect(row.description).to eq("Booking payment")
    expect(row.date_label).to eq("18 Jun")
    expect(row.debit).to eq("—")
    expect(row.credit).to eq("100.00")
    expect(row.balance).to eq("-100.00")
    expect(row.action_label).to eq("—")
  end

  it "shows parent and generated tax charge rows with codes, reference, and running balance" do
    charge_code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    tax_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    parent = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "fb",
      amount: 100,
      transaction_code: charge_code,
      description: "Restaurant charge",
      metadata: { "reference" => "RCPT-42" }
    )
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      transaction_code: tax_code,
      description: "Tax: SST 8% for Restaurant charge",
      metadata: {
        "parent_folio_transaction_id" => parent.id,
        "source_transaction_code_id" => charge_code.id,
        "tax_line" => {
          "type" => "sst",
          "transaction_code_code" => "TAX_SST"
        }
      }
    )

    rows = presenter.posted_rows

    expect(rows.first.code).to eq("FNB")
    expect(rows.first.reference_label).to eq("Ref RCPT-42")
    expect(rows.first.balance).to eq("100.00")
    expect(rows.second.code).to eq("TAX_SST")
    expect(rows.second.reference_label).to eq("Tax linked to FNB · Parent ##{parent.id}")
    expect(rows.second.balance).to eq("108.00")
  end

  it "uses the transaction action policy for reversible parent and tax child labels" do
    manager = create(:user, :superadmin)
    charge_code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    parent = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "fb",
      amount: 100,
      transaction_code: charge_code,
      description: "Restaurant charge"
    )
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      description: "Tax: SST 8% for Restaurant charge",
      metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } }
    )

    rows = described_class.new(booking: booking, hotel: hotel, user: manager).posted_rows

    expect(rows.first.action_label).to eq("Reverse group")
    expect(rows.first.action_kind).to eq(:reverse)
    expect(rows.second.action_label).to eq("Tax reverses with parent")
    expect(rows.second.action_kind).to eq(:disabled)
  end

  it "treats negative refund payments as debit-side balance increases" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -25, description: "Refund")

    row = presenter.posted_rows.first

    expect(row.code).to eq("REFUND")
    expect(row.debit).to eq("25.00")
    expect(row.credit).to eq("—")
    expect(row.balance).to eq("25.00")
  end

  it "shows staff cash payment receipt references and default payment code" do
    staff = create(:user, name: "Aina")
    code = hotel.transaction_codes.find_by!(system_key: "cash_payment")
    create(
      :folio_transaction,
      booking_folio: folio,
      user: staff,
      transaction_type: "payment",
      category: "cash",
      amount: 80,
      transaction_code: code,
      description: "Cash payment",
      metadata: { "payment_source" => "cash", "source_references" => { "receipt_reference" => "RCP-000821" } }
    )

    row = presenter.posted_rows.first

    expect(row.code).to eq("CASH")
    expect(row.reference_label).to eq("Receipt RCP-000821 · Cash · Staff: Aina")
  end

  [
    {
      source: "bank",
      system_key: "bank_payment",
      category: "booking_payment",
      reference_key: "bank_reference",
      reference: "BNK-123",
      expected: "Bank Ref BNK-123 · Bank transfer · Staff: Aina",
      code: "BANK"
    },
    {
      source: "card",
      system_key: "card_payment",
      category: "gateway_payment",
      reference_key: "card_reference",
      reference: "AUTH-123",
      expected: "Card Ref AUTH-123 · Card terminal · Staff: Aina",
      code: "CARD"
    },
    {
      source: "gateway",
      system_key: "gateway_manual_recovery_payment",
      category: "gateway_payment",
      reference_key: "gateway_reference",
      reference: "cap_123",
      expected: "Gateway Ref cap_123 · Manual recovery · Staff: Aina",
      code: "GATEWAY"
    },
    {
      source: "ota",
      system_key: "ota_collected_payment",
      category: "booking_payment",
      reference_key: "ota_reference",
      reference: "AGD-123",
      expected: "OTA Ref AGD-123 · OTA collected · Staff: Aina",
      code: "OTA"
    }
  ].each do |example|
    it "shows #{example[:source]} payment source labels instead of internal categories" do
      staff = create(:user, name: "Aina")
      code = hotel.transaction_codes.find_by!(system_key: example[:system_key])
      create(
        :folio_transaction,
        booking_folio: folio,
        user: staff,
        transaction_type: "payment",
        category: example[:category],
        amount: 80,
        transaction_code: code,
        description: "#{example[:source].humanize} payment",
        metadata: { "payment_source" => example[:source], "source_references" => { example[:reference_key] => example[:reference] } }
      )

      row = presenter.posted_rows.first

      expect(row.code).to eq(example[:code])
      expect(row.credit).to eq("80.00")
      expect(row.reference_label).to eq(example[:expected])
      expect(row.detail_label).to include(example[:expected].split(" · ").second)
      expect(row.reference_label).not_to include("booking_payment")
      expect(row.reference_label).not_to include("gateway_payment")
      expect(row.detail_label).not_to include("Booking payment")
      expect(row.detail_label).not_to include("Gateway payment")
    end
  end

  it "shows manual refund references and default refund code" do
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "refund",
      amount: -25,
      description: "Refund",
      metadata: { "reference" => "RF-102" }
    )

    row = presenter.posted_rows.first

    expect(row.code).to eq("REFUND")
    expect(row.reference_label).to eq("Ref RF-102 · Refund · Manual")
  end

  it "labels upcoming rows as pending projected audit postings" do
    create(:folio_forecasted_charge, booking_folio: folio, amount: 66.60, stay_date: Date.new(2026, 6, 18), charge_kind: "tax", description: "Tax: Service Charge - 2026-06-18")

    row = presenter.forecasted_rows.first

    expect(row.code).to eq("SVC")
    expect(row.description).to eq("Tax: Service Charge - 2026-06-18")
    expect(row.date_label).to eq("18 Jun")
    expect(row.detail_label).to eq("Tax linked to ROOM")
    expect(row.source_label).to eq("Upcoming")
    expect(row.balance).to eq("Pending")
    expect(presenter.forecasted_section_summary).to include("Will post by audit")
    expect(presenter.forecasted_section_summary).to include("upcoming")
  end

  it "shows close folio as not ready when forecasts remain" do
    create(:folio_forecasted_charge, booking_folio: folio, amount: 100, stay_date: Date.new(2026, 6, 18), charge_kind: "accommodation")

    expect(presenter.close_folio_ready?).to be(false)
    expect(presenter.checkout_readiness_label).to eq("Not ready")
    expect(presenter.checkout_status_label).to eq("Not ready for checkout")
    expect(presenter.checkout_status_description).to eq("Guest owes MYR 100.00 · 1 upcoming charge pending")
    expect(presenter.close_folio_status_text).to eq("Checkout: Not ready · Guest owes MYR 100.00 · 1 upcoming charge pending")
  end

  it "shows close folio as a ready placeholder when settled and no forecasts remain" do
    expect(presenter.close_folio_ready?).to be(true)
    expect(presenter.checkout_readiness_label).to eq("Ready")
    expect(presenter.checkout_status_label).to eq("Ready for checkout")
    expect(presenter.checkout_status_description).to eq("Balance settled · No upcoming charges · Payments/refunds synced")
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
