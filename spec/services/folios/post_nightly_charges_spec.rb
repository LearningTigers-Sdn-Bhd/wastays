# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostNightlyCharges do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, performed_by_user: user, status: "running") }

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    start_business_date_audit(hotel)
  end

  it "posts one nightly accommodation and tax charge for an in-house booking" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
    create(:booking_room, booking: booking, subtotal: 200.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    result = described_class.call(night_audit: night_audit, user: user)

    charges = folio.folio_transactions.charge.order(:category)
    expect(charges.count).to eq(2)
    expect(charges.find_by(category: "accommodation").amount).to eq(100.0)
    expect(charges.find_by(category: "tax").amount).to eq(10.0)
    expect(charges.map { |charge| charge.metadata["posting_source"] }.uniq).to eq([ "night_audit" ])
    expect(charges.map(&:night_audit).uniq).to eq([ night_audit ])
    expect(charges.map { |charge| charge.metadata["night_audit_id"] }.uniq).to eq([ night_audit.id ])
    expect(charges.map { |charge| charge.metadata["stay_date"] }.uniq).to eq([ business_date.iso8601 ])
    expect(result.posted.count).to eq(2)
    expect(result.skipped).to be_empty
    expect(result.failed).to be_empty
  end

  it "posts accommodation and tax from financial snapshots" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_posting_snapshot: {
        business_date.iso8601 => [ { "name" => "SST", "amount" => "20.00", "type" => "sst", "source" => "hotel_sst" } ]
      })
    create(:booking_room,
      booking: booking,
      subtotal: 999.0,
      nightly_rate_snapshot: {
        business_date.iso8601 => { "price" => "250.00", "source" => "room_rate" },
        (business_date + 1.day).iso8601 => { "price" => "300.00", "source" => "room_rate" }
      })
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    expect(folio.folio_transactions.charge.find_by(category: "accommodation").amount).to eq(250.0)
    tax = folio.folio_transactions.charge.find_by(category: "tax")
    expect(tax.amount).to eq(20.0)
    expect(tax.metadata["tax_line"]["source"]).to eq("hotel_sst")
  end

  it "posts tax transactions with tax transaction codes from ROOM rule snapshots" do
    hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      guest_country: "Singapore",
      check_in: business_date,
      check_out: business_date + 1.day)
    booking_room = create(:booking_room,
      booking: booking,
      subtotal: 100.0,
      nightly_rate_snapshot: {
        business_date.iso8601 => { "price" => "100.00", "source" => "room_rate" }
      })
    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel,
      check_in: booking.check_in,
      check_out: booking.check_out,
      guest_country: booking.guest_country,
      room_items: [ { quantity: booking_room.quantity, nightly_rate_snapshot: booking_room.nightly_rate_snapshot } ]
    ).call
    booking.update!(tax_lines: snapshot.tax_lines, tax_posting_snapshot: snapshot.tax_posting_snapshot)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    Folios::GenerateForecastedCharges.call(booking_folio: folio)

    described_class.call(night_audit: night_audit, user: user)

    tax_charges = folio.folio_transactions.charge.where(category: "tax").order(:amount)
    expect(tax_charges.map { |transaction| transaction.transaction_code.system_key }).to contain_exactly("sst_tax", "tourism_tax")
    expect(tax_charges.map { |transaction| transaction.metadata.dig("tax_line", "source") }.uniq).to eq([ "transaction_code_tax_rule" ])
    expect(folio.folio_forecasted_charges.actualized.where(charge_kind: "tax").count).to eq(2)
  end

  it "does not post a checkout-day charge" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date - 1.day,
      check_out: business_date)
    create(:booking_room, booking: booking, subtotal: 200.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.not_to change { folio.folio_transactions.charge.count }
  end

  it "does not duplicate nightly charges" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: [ { "name" => "SST", "amount" => "10.00", "type" => "sst" } ])
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    result = nil
    expect { result = described_class.call(night_audit: night_audit, user: user) }
      .not_to change { folio.folio_transactions.charge.count }

    expect(result.skipped.count).to eq(2)
    expect(result.skipped.map { |item| item["reason"] }.uniq).to eq([ "Nightly charge already posted" ])
    expect(night_audit.night_audit_logs.where(action_type: "item_skipped").count).to eq(2)
  end

  it "does not duplicate nightly charges posted on another folio for the same booking" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day)
    booking_room = create(:booking_room, booking: booking, subtotal: 100.0)
    guest_folio = create(:booking_folio, hotel: hotel, booking: booking)
    company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
    key = Folios::ChargePostingKeys.nightly_charge_key(booking: booking, date: business_date, charge_kind: "accommodation", identity: booking_room.id)
    create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", category: "accommodation", amount: 100.0, metadata: { nightly_charge_key: key })

    result = nil
    expect { result = described_class.call(night_audit: night_audit, user: user) }
      .not_to change { guest_folio.folio_transactions.charge.count }

    expect(result.skipped.sole["reason"]).to eq("Nightly charge already posted")
  end

  it "routes ROOM nightly charges by ROOM transaction code" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day)
    create(:booking_room, booking: booking, subtotal: 100.0)
    create(:booking_folio, hotel: hotel, booking: booking)
    company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

    described_class.call(night_audit: night_audit, user: user)

    charge = company_folio.folio_transactions.charge.sole
    expect(charge.category).to eq("accommodation")
    expect(charge.transaction_code).to eq(room_code)
    expect(charge.metadata["route_source"]).to eq("routing_rule")
  end

  it "routes scheduled SST and TTX nightly taxes by their own transaction codes" do
    hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    ttx_code = hotel.transaction_codes.find_by!(system_key: "tourism_tax")
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_posting_snapshot: {
        business_date.iso8601 => [
          { "name" => "SST", "amount" => "8.00", "type" => "sst", "transaction_code_id" => sst_code.id },
          { "name" => "Tourism Tax", "amount" => "10.00", "type" => "tourism_tax", "transaction_code_id" => ttx_code.id }
        ]
      })
    create(:booking_room, booking: booking, subtotal: 100.0)
    guest_folio = create(:booking_folio, hotel: hotel, booking: booking)
    company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: sst_code, target_folio: company_folio)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: ttx_code, target_folio: guest_folio)

    described_class.call(night_audit: night_audit, user: user)

    expect(company_folio.folio_transactions.charge.find_by(transaction_code: sst_code).amount).to eq(8.0)
    expect(guest_folio.folio_transactions.charge.find_by(transaction_code: ttx_code).amount).to eq(10.0)
  end

  it "records a missing folio as a skipped item" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day)
    create(:booking_room, booking: booking, subtotal: 100.0)

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.skipped.sole).to include("booking_id" => booking.id, "reason" => "Booking has no folio")
  end

  it "records a failed charge item before raising" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day)
    create(:booking_room, booking: booking, subtotal: 100.0)
    create(:booking_folio, hotel: hotel, booking: booking)
    allow_any_instance_of(Folios::InsertTransaction).to receive(:call).and_return(OpenStruct.new(success?: false, error: "posting failed"))

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.to raise_error("Failed to post nightly folio charge: posting failed")

    item = night_audit.night_audit_logs.find_by!(action_type: "item_failed").metadata["item"]
    expect(item).to include("booking_id" => booking.id, "reason" => "posting failed")
  end

  it "posts separate tax lines with the same tax type" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: [
        { "name" => "Local Tax", "amount" => "5.00", "type" => "local" },
        { "name" => "Local Tax", "amount" => "3.00", "type" => "local" }
      ])
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    tax_charges = folio.folio_transactions.charge.where(category: "tax")
    expect(tax_charges.count).to eq(2)
    expect(tax_charges.sum(:amount)).to eq(8.0)
  end

  it "allocates rounding remainder to the final billable night" do
    final_night = business_date + 2.days
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: final_night)
    start_business_date_audit(hotel)
    final_night_audit = create(:night_audit, hotel: hotel, business_date: final_night, performed_by_user: user, status: "running")
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 3.days)
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: final_night_audit, user: user)

    expect(folio.folio_transactions.charge.sole.amount).to eq(33.34)
  end

  it "actualizes forecast charges when posting nightly charges" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
    create(:booking_room, booking: booking, subtotal: 200.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    Folios::GenerateForecastedCharges.call(booking_folio: folio)

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.to change { folio.folio_forecasted_charges.forecast.count }
      .from(4)  # 2 accommodation + 2 tax
      .to(2)    # 2 remaining forecasts for future nights

    actualized = folio.folio_forecasted_charges.actualized
    expect(actualized.count).to eq(2)
    expect(actualized.map(&:actualizing_transaction)).to all(be_present)
  end

  it "actualizes a forecast when retrying after the nightly charge already exists" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day)
    booking_room = create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    Folios::GenerateForecastedCharges.call(booking_folio: folio)
    existing_transaction = create(:folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "accommodation",
      amount: 100.0,
      posting_date: business_date,
      metadata: { nightly_charge_key: [ booking.id, business_date.iso8601, "accommodation", booking_room.id ].join(":") })

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.not_to change { folio.folio_transactions.charge.count }

    forecast = folio.folio_forecasted_charges.sole
    expect(forecast.reload.status).to eq("actualized")
    expect(forecast.actualizing_transaction).to eq(existing_transaction)
  end
end
