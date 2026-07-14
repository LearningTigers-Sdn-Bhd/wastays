# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Billing Pipeline", type: :integration do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:user) { create(:user) }

  let(:agent_account) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      account_type: "travel_agent",
      direct_bill_enabled: true,
      payment_terms_days: 30,
      credit_currency: "MYR",
      corporate_account: create(:account, :corporate, name: "Sunset Travel Agency")
    )
  end

  def booking_billed_to(agent_account)
    booking = create(:booking, hotel: hotel, status: "checked_in", currency: "MYR", hotel_corporate_account: agent_account)
    create(:booking_room, booking: booking, subtotal: 300.0)
    booking
  end

  # Posts a real charge for every open forecast on the folio, matching the
  # posting key Folios::CloseForCheckout looks for, instead of hand-rolling
  # a charge that would leave the auto-generated forecast "unsettled."
  def post_forecasted_charges!(folio)
    folio.folio_forecasted_charges.forecast.each do |forecast|
      key = Folios::ChargePostingKeys.nightly_charge_key(
        booking: folio.booking, date: forecast.stay_date, charge_kind: forecast.charge_kind, identity: forecast.identity
      )
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: forecast.charge_kind,
        amount: forecast.amount,
        metadata: { nightly_charge_key: key })
    end
  end

  it "routes a group of agent-booked rooms through one billing party into a shared statement and aging report" do
    booking_a = booking_billed_to(agent_account)
    booking_b = booking_billed_to(agent_account)

    folio_a = Folios::InitializeForBooking.call(booking: booking_a, user: user)
    folio_b = Folios::InitializeForBooking.call(booking: booking_b, user: user)

    # Both rooms route to the same agent ledger, sharing one BookingBillingParty.
    expect(folio_a.payer_type).to eq("company")
    expect(folio_b.payer_type).to eq("company")
    expect(folio_a.hotel_corporate_account).to eq(agent_account)
    expect(folio_b.hotel_corporate_account).to eq(agent_account)
    # Each booking gets its own BookingBillingParty (belongs_to :booking), but both point at the same agent ledger.
    expect(folio_a.booking_billing_party.hotel_corporate_account).to eq(agent_account)
    expect(folio_b.booking_billing_party.hotel_corporate_account).to eq(agent_account)
    expect(folio_a.booking_billing_party).not_to eq(folio_b.booking_billing_party)

    post_forecasted_charges!(folio_a)
    post_forecasted_charges!(folio_b)

    result_a = Folios::CloseForCheckout.call(booking: booking_a, user: user, options: { direct_bill_folio_ids: [ folio_a.id ] })
    result_b = Folios::CloseForCheckout.call(booking: booking_b, user: user, options: { direct_bill_folio_ids: [ folio_b.id ] })

    expect(result_a.success?).to be(true)
    expect(result_b.success?).to be(true)

    invoice_a = folio_a.reload.ar_invoice
    invoice_b = folio_b.reload.ar_invoice
    expect(invoice_a).to be_present
    expect(invoice_b).to be_present
    expect(invoice_a.hotel_corporate_account).to eq(agent_account)
    expect(invoice_a.amount).to eq(300.0)
    expect(invoice_a.due_on).to eq(hotel.current_business_date + 30.days)

    # Aging report aggregates both bookings under the one agent account.
    aging = ArInvoices::AgingReport.call(hotel: hotel, as_of_date: hotel.current_business_date)
    row = aging.rows.find { |r| r.hotel_corporate_account == agent_account }
    expect(row).to be_present
    expect(row.total_outstanding).to eq(600.0)

    # Statement of account for the agent covers both invoices.
    statement = Reports::AccountsReceivable::GenerateStatementRecords.call(
      hotel: hotel,
      hotel_corporate_account: agent_account,
      start_date: hotel.current_business_date - 1.day,
      end_date: hotel.current_business_date
    )
    invoice_references = statement.ledger_rows.select { |row| row.record_type == "Invoice" }.map(&:reference)
    expect(invoice_references).to include(invoice_a.formatted_invoice_number, invoice_b.formatted_invoice_number)
  end

  it "leaves an agent-booked folio open at checkout when direct billing is not selected" do
    booking = booking_billed_to(agent_account)
    folio = Folios::InitializeForBooking.call(booking: booking, user: user)
    post_forecasted_charges!(folio)

    result = Folios::CloseForCheckout.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to include("balance")
    expect(folio.reload.status).to eq("open")
  end
end
