# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::InitializeForBooking do
  let(:booking) { create(:booking, check_in: Date.current, tourism_tax_amount: 0, tax_lines: [ { "name" => "SST", "amount" => "12.00" } ]) }
  let(:user) { create(:user) }

  before do
    create(:booking_room, booking: booking, subtotal: 200.0)
  end

  it "creates a folio with captured payments as booking payments" do
    payment_transaction = create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

    folio = described_class.call(booking: booking, user: user)

    expect(folio).to be_persisted
    expect(folio.booking).to eq(booking)
    expect(folio.hotel).to eq(booking.hotel)
    expect(folio.folio_transactions.charge.count).to eq(0)
    payment = folio.folio_transactions.payment.sole
    expect(payment.category).to eq("booking_payment")
    expect(payment.metadata["payment_transaction_id"]).to eq(payment_transaction.id)
    expect(folio.outstanding_balance).to eq(-100.0)
  end

  it "generates forecasted charges after folio creation" do
    folio = described_class.call(booking: booking, user: user)

    forecasts = folio.folio_forecasted_charges.forecast.order(:charge_kind)
    expect(forecasts.count).to eq(2)
    expect(forecasts[0].charge_kind).to eq("accommodation")
    expect(forecasts[0].amount).to eq(200.0)
    expect(forecasts[0].stay_date).to eq(Date.current)
    expect(forecasts[1].charge_kind).to eq("tax")
  end

  it "returns an existing folio without posting duplicate transactions" do
    existing_folio = create(:booking_folio, booking: booking)

    expect {
      result = described_class.call(booking: booking, user: user)
      expect(result).to eq(existing_folio)
    }.not_to change(FolioTransaction, :count)
  end

  it "returns the winner's folio when a concurrent insert wins the race" do
    existing_folio = described_class.call(booking: booking, user: user)

    # Simulate the race: our existence check sees no folio (so we attempt the
    # insert), but the partial unique index rejects it because the winner's
    # primary folio already exists. Reload then hands back the winner's folio.
    allow(booking).to receive(:booking_folio).and_return(nil, existing_folio)

    result = nil
    expect {
      result = described_class.call(booking: booking, user: user)
    }.not_to raise_error
    expect(result).to eq(existing_folio)
  end

  it "rolls back folio creation when captured payments cannot be synced" do
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)
    failed_result = Folios::TransactionResult.failure("posting blocked")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    expect {
      described_class.call(booking: booking, user: user)
    }.to raise_error(RuntimeError, /posting blocked/)

    expect(booking.reload.booking_folio).to be_nil
  end

  it "blocks missing folio creation while night audit is running" do
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    expect do
      described_class.call(booking: booking, user: user)
    end.to raise_error(NightAudits::OperationalChangeGuard::OperationalChangeBlocked)

    expect(booking.reload.booking_folio).to be_nil
  end

  it "allows system confirmation to create a non-posting folio while night audit is running" do
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    folio = described_class.call(
      booking: booking,
      user: nil,
      options: { system_folio_initialization: true, posting_source: "booking_confirmation" }
    )

    expect(folio).to be_persisted
    expect(folio.folio_transactions).to be_empty
  end

  it "allows system initialization regardless of the caller's posting source" do
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    folio = described_class.call(
      booking: booking,
      user: nil,
      options: { system_folio_initialization: true, posting_source: "group_booking_confirmation" }
    )

    expect(folio).to be_persisted
    expect(folio.folio_transactions).to be_empty
  end

  it "routes the primary folio to the agent's ledger when booked via an active agent account" do
    hotel_corporate_account = create(:hotel_corporate_account, hotel: booking.hotel, account_type: "travel_agent")
    booking.update!(hotel_corporate_account: hotel_corporate_account)

    folio = described_class.call(booking: booking, user: user)

    expect(folio.payer_type).to eq("company")
    expect(folio.folio_type).to eq("external")
    expect(folio.hotel_corporate_account).to eq(hotel_corporate_account)
    party = folio.booking_billing_party
    expect(party).to be_present
    expect(party.party_kind).to eq("company")
    expect(party.hotel_corporate_account).to eq(hotel_corporate_account)
    expect(booking.booking_billing_parties).to eq([ party ])
  end

  it "falls back to a guest folio when the linked agent account is suspended" do
    hotel_corporate_account = create(:hotel_corporate_account, hotel: booking.hotel, account_type: "travel_agent", status: "suspended")
    booking.update!(hotel_corporate_account: hotel_corporate_account)

    folio = described_class.call(booking: booking, user: user)

    expect(folio.payer_type).to eq("guest")
    expect(folio.folio_type).to eq("guest")
    expect(booking.booking_billing_parties).to be_empty
  end

  it "does not let system confirmation bypass payment posting guards during night audit" do
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    expect {
      described_class.call(
        booking: booking,
        user: nil,
        options: { system_folio_initialization: true, posting_source: "booking_confirmation" }
      )
    }.to raise_error(/currently in night audit/)

    expect(booking.reload.booking_folio).to be_nil
  end
end
