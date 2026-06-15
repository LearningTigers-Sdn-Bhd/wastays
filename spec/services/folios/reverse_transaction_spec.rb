# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ReverseTransaction, type: :service do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

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
    Folios::GenerateForecastedCharges.call(booking_folio: folio)
    forecast = folio.folio_forecasted_charges.forecast.sole
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 120,
      posting_date: Date.current,
      metadata: {
        "nightly_charge_key" => Folios::ChargePostingKeys.nightly_charge_key(
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
    Folios::GenerateForecastedCharges.call(booking_folio: folio)
    forecast = folio.folio_forecasted_charges.forecast.sole
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 120,
      posting_date: Date.current,
      metadata: {
        "nightly_charge_key" => Folios::ChargePostingKeys.nightly_charge_key(
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
