# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::ReverseTransaction, type: :service, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio) }

  it "creates a negative adjustment for a charge reversal" do
    transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 120)

    expect {
      @result = described_class.call(
        transaction: transaction,
        user: user,
        correction_reason: "Posting error",
        correction_note: "Wrong room charge"
      )
    }.to change(FinancialAuditEvent, :count).by(1)

    result = @result

    expect(result).to be_success
    expect(result.transaction).to have_attributes(
      transaction_type: "adjustment",
      category: "correction",
      amount: -120.to_d,
      reversal_of_transaction: transaction,
      correction_reason: "Posting error",
      correction_note: "Wrong room charge"
    )
    expect(transaction.reload.voided_by_transaction).to eq(result.transaction)
    expect(FinancialAuditEvent.last.event_type).to eq("folio_transaction_reversed")
  end

  it "creates a refund-style payment for a positive payment reversal" do
    transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 80)

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Payment error",
      correction_note: "Duplicate payment"
    )

    expect(result).to be_success
    expect(result.transaction).to have_attributes(
      transaction_type: "payment",
      category: "refund",
      amount: -80.to_d,
      reversal_of_transaction: transaction
    )
  end

  it "creates a positive charge/correction for a refund (negative payment) reversal" do
    transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -50)

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Refund error",
      correction_note: "Duplicate refund"
    )

    expect(result).to be_success
    expect(result.transaction).to have_attributes(
      transaction_type: "adjustment",
      category: "correction",
      amount: 50.to_d,
      reversal_of_transaction: transaction
    )
  end

  it "rejects a missing correction reason" do
    transaction = create(:folio_transaction, booking_folio: folio)

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "",
      correction_note: "Wrong posting"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Correction reason can't be blank.")
  end

  it "rejects a missing correction note" do
    transaction = create(:folio_transaction, booking_folio: folio)

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Posting error",
      correction_note: ""
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Correction note can't be blank.")
  end

  it "rejects already reversed transactions" do
    transaction = create(:folio_transaction, booking_folio: folio)
    first_result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Posting error",
      correction_note: "Wrong posting"
    )

    second_result = described_class.call(
      transaction: transaction.reload,
      user: user,
      correction_reason: "Posting error",
      correction_note: "Duplicate reversal"
    )

    expect(first_result).to be_success
    expect(second_result).not_to be_success
    expect(second_result.error).to eq("Transaction has already been reversed.")
  end

  it "rejects reversal transactions" do
    transaction = create(:folio_transaction, booking_folio: folio)
    reversal = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction", amount: -100, reversal_of_transaction: transaction)

    result = described_class.call(
      transaction: reversal,
      user: user,
      correction_reason: "Posting error",
      correction_note: "Reverse reversal"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Reversal transactions cannot be reversed.")
  end

  it "reverses a taxable parent and generated tax children atomically" do
    parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100, description: "Restaurant charge")
    tax = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      description: "SST",
      metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } }
    )

    expect {
      @result = described_class.call(
        transaction: parent,
        user: user,
        correction_reason: "Posting error",
        correction_note: "Wrong amount"
      )
    }.to change(FolioTransaction, :count).by(2)

    expect(@result).to be_success
    parent_reversal = parent.reload.voided_by_transaction
    tax_reversal = tax.reload.voided_by_transaction
    expect(parent_reversal).to have_attributes(amount: -100.to_d, reversal_of_transaction: parent)
    expect(tax_reversal).to have_attributes(amount: -8.to_d, reversal_of_transaction: tax)
    expect(@result.transactions).to match_array([ parent_reversal, tax_reversal ])
  end

  it "reverses generated tax children posted on another folio" do
    tax_folio = create(:booking_folio, :secondary, booking: folio.booking, hotel: folio.hotel)
    parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100, description: "Restaurant charge")
    tax = create(
      :folio_transaction,
      booking_folio: tax_folio,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      description: "Tourism Tax",
      metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "tourism_tax" } }
    )

    result = described_class.call(
      transaction: parent,
      user: user,
      correction_reason: "Posting error",
      correction_note: "Wrong amount"
    )

    expect(result).to be_success
    expect(parent.reload.voided_by_transaction.booking_folio).to eq(folio)
    expect(tax.reload.voided_by_transaction.booking_folio).to eq(tax_folio)
  end

  it "rejects direct reversal of generated tax children" do
    parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
    tax = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } }
    )

    expect {
      @result = described_class.call(
        transaction: tax,
        user: user,
        correction_reason: "Posting error",
        correction_note: "Reverse tax only"
      )
    }.not_to change(FolioTransaction, :count)

    expect(@result).not_to be_success
    expect(@result.error).to eq("Generated tax rows reverse with their parent charge.")
    expect(tax.reload.voided_by_transaction).to be_nil
  end

  it "rolls back the full tax group when any reversal row fails" do
    parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
    tax = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } }
    )

    allow_any_instance_of(Folios::Transactions::ReverseTransaction).to receive(:reversal_category).and_wrap_original do |method, original|
      original == tax ? "not_allowed" : method.call(original)
    end

    expect {
      @result = described_class.call(
        transaction: parent,
        user: user,
        correction_reason: "Posting error",
        correction_note: "Rollback group"
      )
    }.not_to change(FolioTransaction, :count)

    expect(@result).not_to be_success
    expect(parent.reload.voided_by_transaction).to be_nil
    expect(tax.reload.voided_by_transaction).to be_nil
  end

  it "rejects gateway payment reversal from the folio ledger" do
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 80,
      metadata: { "payment_transaction_id" => "123", "posting_source" => "gateway_payment" }
    )

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Payment error",
      correction_note: "Use refund workflow"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Gateway payments must use the payment refund or reconciliation workflow.")
  end

  it "records override metadata when reversing onto a closed folio" do
    folio.update!(status: "closed")
    transaction = create(:folio_transaction, booking_folio: folio)

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Manager override",
      correction_note: "Correct closed folio"
    )

    expect(result).to be_success
    expect(result.transaction.metadata).to include(
      "override_closed_folio" => true,
      "override_reason" => "Manager override",
      "override_note" => "Correct closed folio",
      "posted_by_user_id" => user.id
    )
  end

  it "supersedes the actualized forecast for a reversed nightly charge and creates a new pending forecast" do
    booking = create(:booking, status: "checked_in", check_in: Date.current, check_out: Date.current + 1.day)
    booking_room = create(:booking_room, booking: booking, subtotal: 120)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)
    forecast = folio.folio_forecasted_charges.forecast.sole
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 120,
      posting_date: Date.current,
      metadata: {
        "nightly_charge_key" => Folios::Charges::ChargePostingKeys.nightly_charge_key(
          booking: booking,
          date: Date.current,
          charge_kind: "accommodation",
          identity: booking_room.id
        ),
        "stay_date" => Date.current.iso8601,
        "charge_kind" => "accommodation",
        "forecast_identity" => booking_room.id.to_s
      }
    )
    forecast.actualize!(transaction: transaction)

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Posting error",
      correction_note: "Wrong room charge"
    )

    expect(result).to be_success
    expect(forecast.reload.status).to eq("superseded")
    pending = folio.folio_forecasted_charges.forecast.sole
    expect(pending).to have_attributes(
      stay_date: Date.current,
      charge_kind: "accommodation",
      identity: booking_room.id.to_s,
      amount: 120.to_d
    )
  end

  it "does not recreate a pending forecast when reversing a nightly charge for a terminal booking" do
    booking = create(:booking, status: "checked_in", check_in: Date.current, check_out: Date.current + 1.day)
    booking_room = create(:booking_room, booking: booking, subtotal: 120)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)
    forecast = folio.folio_forecasted_charges.forecast.sole
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 120,
      posting_date: Date.current,
      metadata: {
        "nightly_charge_key" => Folios::Charges::ChargePostingKeys.nightly_charge_key(
          booking: booking,
          date: Date.current,
          charge_kind: "accommodation",
          identity: booking_room.id
        ),
        "stay_date" => Date.current.iso8601,
        "charge_kind" => "accommodation",
        "forecast_identity" => booking_room.id.to_s
      }
    )
    forecast.actualize!(transaction: transaction)
    booking.transition_status_to!("completed", event: "check_out")

    result = described_class.call(
      transaction: transaction,
      user: user,
      correction_reason: "Posting error",
      correction_note: "Wrong room charge"
    )

    expect(result).to be_success
    expect(forecast.reload.status).to eq("superseded")
    expect(folio.folio_forecasted_charges.forecast).to be_none
  end
end
