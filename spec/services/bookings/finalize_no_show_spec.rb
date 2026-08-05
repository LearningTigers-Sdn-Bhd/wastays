# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::FinalizeNoShow do
  it "posts the standard charge and finalizes a detected no-show booking" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    room_type = create(:room_type, hotel: hotel)
    business_date = Date.current
    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("no_show")
    expect(booking.booking_folio.folio_transactions.charge.where(category: "no_show_charge").sole.amount).to eq(100.0)
    expect(booking.booking_folio).to be_open
    expect(result.skipped_folios.sole.balance).to eq(100.0)
  end

  describe "the hotel's no-show policy" do
    def configure_no_show_policy(hotel, **attributes)
      ReservationPolicies::EnsureDefaults.call(hotel)
      hotel.hotel_reservation_policies.find_by!(policy_type: "no_show").tap { |policy| policy.update!(**attributes) }
    end

    def no_show_booking(hotel, business_date, nights: 3, subtotal: 300.0)
      create(
        :booking,
        hotel: hotel,
        status: "no_show_detected",
        no_show_detected_business_date: business_date,
        check_in: business_date,
        check_out: business_date + nights.days,
        tax_lines: []
      ).tap { |booking| create(:booking_room, booking: booking, subtotal: subtotal) }
    end

    it "posts nothing at all when the policy is switched off" do
      hotel = create(:hotel)
      user = create(:user, account: hotel.account)
      business_date = Date.current
      configure_no_show_policy(hotel, active: false)
      booking = no_show_booking(hotel, business_date)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

      result = described_class.call(booking: booking, user: user)

      expect(result.success?).to be(true)
      expect(booking.reload.status).to eq("no_show")
      expect(booking.booking_folio.folio_transactions.charge).to be_empty
    end

    # The policy is nights-only by database constraint precisely so the fee and
    # the per-night snapshot tax lines always describe the same nights.
    it "bills as many nights as the policy charges, with each night's snapshot tax" do
      hotel = create(:hotel, sst_enabled: true)
      user = create(:user, account: hotel.account)
      business_date = Date.current
      configure_no_show_policy(hotel, rate_value: 2)
      booking = no_show_booking(hotel, business_date)
      booking.update!(tax_posting_snapshot: {
        business_date.iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst_tax" } ],
        (business_date + 1.day).iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst_tax" } ],
        (business_date + 2.days).iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst_tax" } ]
      })
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

      expect(described_class.call(booking: booking, user: user).success?).to be(true)

      charges = booking.reload.booking_folio.folio_transactions.charge
      room_charges = charges.where(category: "no_show_charge")
      tax_charges = charges.where(category: "tax")
      expect(room_charges.count).to eq(2)
      expect(room_charges.sum(:amount)).to eq(200.0)
      # Two nights billed, two nights of tax — never the whole stay's tax, and
      # never one night's tax on a two-night fee.
      expect(tax_charges.count).to eq(2)
      expect(tax_charges.sum(:amount)).to eq(12.0)
      expect(room_charges.map { |charge| charge.metadata["stay_date"] })
        .to contain_exactly(business_date.iso8601, (business_date + 1.day).iso8601)
    end

    it "never bills past the end of the stay" do
      hotel = create(:hotel)
      user = create(:user, account: hotel.account)
      business_date = Date.current
      configure_no_show_policy(hotel, rate_value: 5)
      booking = no_show_booking(hotel, business_date, nights: 2, subtotal: 200.0)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

      expect(described_class.call(booking: booking, user: user).success?).to be(true)

      expect(booking.reload.booking_folio.folio_transactions.charge.where(category: "no_show_charge").count).to eq(2)
    end
  end

  # No-show posts its tax lines from the booking's own tax snapshot, which is the
  # right treatment for a historical night. It must never also inherit ROOM's live
  # tax rules the way late checkout and early departure do, or every no-show would
  # be taxed twice. TransactionCodes::Resolver::TAX_RULE_SOURCE_SYSTEM_KEYS omits
  # no_show_revenue for exactly this reason.
  it "does not attach ROOM's live tax rules on top of its snapshot taxes" do
    hotel = create(:hotel, sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
    user = create(:user, account: hotel.account)
    room_type = create(:room_type, hotel: hotel)
    business_date = Date.current
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    room_code = hotel.transaction_codes.find_by(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)

    expect(described_class.call(booking: booking, user: user).success?).to be(true)

    transactions = booking.booking_folio.folio_transactions.charge
    expect(transactions.where(category: "no_show_charge").sole.amount).to eq(100.0)
    expect(transactions.where(category: "tax")).to be_empty
  end

  it "records the staff reason on no-show audit metadata" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = hotel.current_business_date
    reason = "Guest did not arrive after follow-up call"
    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: []
    )
    create(:booking_room, booking: booking, subtotal: 100.0)

    result = described_class.call(booking: booking, user: user, reason: reason)

    expect(result).to be_success
    audit = BookingAuditLog.where(auditable: booking, action_type: "no_show").sole
    expect(audit.metadata["reason"]).to eq(reason)
  end

  it "does not post tourism tax but keeps other no-show taxes" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = hotel.current_business_date
    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_posting_snapshot: {
        business_date.iso8601 => [
          { "name" => "Tourism Tax", "type" => "tourism_tax", "amount" => "10.00" },
          { "name" => "Service Tax", "type" => "sst", "amount" => "6.00" }
        ]
      }
    )
    create(:booking_room, booking: booking, subtotal: 100.0)

    result = described_class.call(booking: booking, user: user)

    expect(result).to be_success
    tax_transactions = booking.reload.booking_folio.folio_transactions.charge.where(category: "tax")
    expect(tax_transactions.pluck(:amount)).to contain_exactly(6.to_d)
    expect(tax_transactions.sole.metadata.dig("tax_line", "type")).to eq("sst")
  end

  it "closes a settled no-show folio and records operation and financial audit events" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = hotel.current_business_date
    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: []
    )
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "cash",
      amount: 100.0
    )

    expect {
      @result = described_class.call(booking: booking, user: user)
    }.to change(FolioOperationLog.where(operation_type: "close_folio"), :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "no_show_folio_closed"), :count).by(1)

    expect(@result).to be_success
    expect(@result.closed_folios).to contain_exactly(folio)
    expect(folio.reload).to be_closed
    expect(FolioOperationLog.last.metadata["source"]).to eq("no_show_finalization")
  end

  it "supersedes forecasts on every folio and closes only zero-balance folios" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = hotel.current_business_date
    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: []
    )
    create(:booking_room, booking: booking, subtotal: 100.0)
    primary = create(:booking_folio, booking: booking, hotel: hotel)
    secondary = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    create(:folio_forecasted_charge, booking_folio: primary)
    secondary_forecast = create(:folio_forecasted_charge, booking_folio: secondary)

    result = described_class.call(booking: booking, user: user)

    expect(result).to be_success
    expect(primary.reload).to be_open
    expect(secondary.reload).to be_closed
    expect(primary.folio_forecasted_charges.pluck(:status)).to all(eq("superseded"))
    expect(secondary_forecast.reload.status).to eq("superseded")
    expect(result.closed_folios).to contain_exactly(secondary)
    expect(result.skipped_folios.map(&:folio)).to contain_exactly(primary)
  end

  it "links audit-generated no-show charges directly to the active night audit" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = hotel.current_business_date
    booking = create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: business_date,
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: []
    )
    create(:booking_room, booking: booking, subtotal: 100.0)
    start_business_date_audit(hotel)
    audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running")

    result = described_class.call(booking: booking, user: user, night_audit: audit, automatic: true)

    expect(result.success?).to be(true)
    charge = booking.reload.booking_folio.folio_transactions.charge.sole
    expect(charge.night_audit).to eq(audit)
    expect(charge.metadata["night_audit_id"]).to eq(audit.id)
    expect(charge.metadata["posting_source"]).to eq("no_show")
  end

  it "blocks staff no-show finalization while night audit is running" do
    booking = create(:booking, status: "no_show_detected", no_show_detected_business_date: Date.current)
    start_business_date_audit(booking.hotel)

    result = described_class.call(booking: booking, user: create(:user))

    expect(result.success?).to be(false)
    expect(result.error).to eq(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
    expect(booking.reload.status).to eq("no_show_detected")
  end
end
