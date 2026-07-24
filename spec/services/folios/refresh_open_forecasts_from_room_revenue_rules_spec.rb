# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::RefreshOpenForecastsFromRoomRevenueRules do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel, sst_enabled: true, accounting_business_date: business_date) }
  let(:user) { create(:user, account: hotel.account) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      guest_country: "Malaysia",
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_posting_snapshot: {
        business_date.iso8601 => [ { "name" => "Original Tax", "amount" => "5.00", "type" => "original", "source" => "legacy" } ]
      })
  end
  let!(:booking_room) { create(:booking_room, booking: booking, subtotal: 100.0) }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }

  before do
    hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    Folios::SyncForecastedCharges.call(booking_folio: folio)
  end

  it "refreshes unposted forecasts from current ROOM tax rules" do
    original_tax_forecast = folio.folio_forecasted_charges.forecast.find_by!(charge_kind: "tax")

    result = described_class.call(hotel: hotel, actor: user)

    expect(result.folios_scanned).to eq(1)
    expect(result.bookings_updated).to eq(1)
    expect(result.forecasts_superseded).to eq(1)
    expect(result.forecasts_created).to eq(1)
    expect(original_tax_forecast.reload.status).to eq("superseded")

    active_tax_forecast = folio.folio_forecasted_charges.forecast.find_by!(charge_kind: "tax")
    expect(active_tax_forecast.description).to eq("Tax: SST 8% - #{business_date}")
    expect(active_tax_forecast.amount).to eq(8.0)
    expect(booking.reload.tax_posting_snapshot.dig(business_date.iso8601, 0, "source")).to eq("transaction_code_tax_rule")
  end

  it "does not mutate posted transactions" do
    posted_transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "tax",
      amount: 5.0,
      posting_date: business_date,
      metadata: { nightly_charge_key: [ booking.id, business_date.iso8601, "tax", "original:0" ].join(":") }
    )

    expect {
      described_class.call(hotel: hotel, actor: user)
    }.not_to change { posted_transaction.reload.attributes.except("updated_at") }
  end

  it "records an immutable financial audit event with refresh counts" do
    described_class.call(hotel: hotel, actor: user)

    event = hotel.financial_audit_events.find_by!(event_type: "folio_forecasts_refreshed")
    expect(event.actor).to eq(user)
    expect(event.source).to eq("transaction_codes")
    expect(event.metadata).to include(
      "folios_scanned" => 1,
      "bookings_updated" => 1,
      "forecasts_superseded" => 1,
      "forecasts_created" => 1,
      "forecasts_changed" => 2
    )
  end
end
