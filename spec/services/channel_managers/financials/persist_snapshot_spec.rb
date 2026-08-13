require "rails_helper"

RSpec.describe ChannelManagers::Financials::PersistSnapshot do
  it "persists Aurora OTA accommodation, components, FX remainder, variance, occupancy, and tax projections" do
    hotel = create(:hotel, default_currency: "MYR")
    create(:channel_mapping, mappable: hotel, provider: "channex", external_id: "prop_aurora")
    room_type = create(:room_type, hotel: hotel, max_adults: 2)
    rate_plan = create(:rate_plan, hotel: hotel, room_type: room_type, currency: "MYR")
    assignment = room_type.room_type_rate_plans.find_by!(rate_plan: rate_plan)
    create(:channel_mapping, mappable: room_type, provider: "channex",
      external_id: "db7b5c2d-ffb6-4b1d-9290-2a7e9c4423da")
    create(:channel_mapping, mappable: assignment, provider: "channex",
      external_id: "e12016f5-71bf-4f79-ba19-27d643198df3")
    create(:exchange_rate, base_currency: "USD", currency_code: "MYR", rate: 4.1)
    create(:hotel_tax, hotel: hotel, name: "VAT (14%)", code: "VAT14", rate_type: "percentage",
      amount: 14, charge_type: "tax", enabled: true)
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.new(2026, 8, 11),
      price: 1485, currency: "MYR")
    create(:room_inventory, room_type: room_type, date: Date.new(2026, 8, 11), quantity: 2)
    BookingSource.find_or_create_by!(key: "booking_com") do |source|
      source.label = "Booking.com"
      source.kind = "ota"
    end
    payload = JSON.parse(Rails.root.join("spec/fixtures/channel_managers/channex_aurora_financial_booking.json").read)
    booking_data = ChannelManagers::ChannexAdapter.new(hotel: hotel).ingest_booking(payload: payload)
    booking_data[:guest_details].merge!(email: "aurora@example.com", phone: "+60123456789")

    result = ChannelManagers::IngestBookingService.new(booking_data: booking_data).call

    expect(result).to be_success
    booking = result.booking.reload
    snapshot = OtaFinancialSnapshot.current.find_by!(booking: booking)
    expect(booking).to have_attributes(total_amount: 2201.54.to_d, adults: 2)
    expect(booking.booking_rooms.first).to have_attributes(subtotal: 1488.79.to_d)
    expect(booking.booking_rooms.first.occupancy_snapshot).to include("adults" => 2)
    expect(booking.booking_rooms.first.nightly_rate_snapshot.dig("2026-08-11", "price")).to eq("1488.79")
    expect(snapshot).to have_attributes(
      original_accommodation_amount: 363.12.to_d, accommodation_amount: 1488.79.to_d,
      expected_pms_accommodation_amount: 1485.to_d, variance_amount: 3.79.to_d,
      reconciliation_status: "accepted_fx_variance", gross_amount: 2201.54.to_d
    )
    expect(snapshot.ota_financial_components.order(:stable_key).pluck(:component_kind, :amount)).to contain_exactly(
      [ "accommodation", 1488.79.to_d ], [ "service", 504.30.to_d ], [ "tax", 208.45.to_d ]
    )
    tax = snapshot.ota_financial_components.find_by!(component_kind: "tax")
    expect(tax.allocation_rounding_amount).to eq(0.01.to_d)
    expect(booking.tax_posting_snapshot.dig("2026-08-11", 0)).to include(
      "amount" => "208.45", "source" => "ota_supplied", "ota_financial_component_id" => tax.id
    )
    lines = Folios::Reads::ForecastedChargeLines.call(booking: booking)
    expect(lines.map { |line| [ line[:charge_kind], line[:amount] ] }).to contain_exactly(
      [ "accommodation", 1488.79.to_d ], [ "ota_service", 504.30.to_d ], [ "tax", 208.45.to_d ]
    )
    expect(lines.sum { |line| line[:amount] }).to eq(2201.54.to_d)
    expect(snapshot.metadata.to_json).not_to match(/card_number|cvv|token|4111111111111111/)
  end


  it "expands explicitly nightly booking components into dated immutable facts" do
    hotel = create(:hotel, default_currency: "MYR")
    booking = create(:booking, hotel: hotel, check_in: Date.new(2026, 9, 1), check_out: Date.new(2026, 9, 3))
    room = create(:booking_room, booking: booking, subtotal: 100)
    financials = {
      provider: "channex", channel_manager_reference: "cadence-1", provider_revision_id: "cadence-rev-1",
      currency: "MYR", converted_currency: "MYR", gross_amount: 130.to_d, converted_gross_amount: 130.to_d,
      exchange_rate: 1.to_d, exchange_rate_source: "same_currency", conversion_rounding_amount: 0.to_d,
      rooms: [ {
        position: 1, quantity: 1, room_type: room.room_type, rate_plan: room.rate_plan,
        amount: 100.to_d, converted_amount: 100.to_d,
        days: [
          { date: "2026-09-01", amount: 50.to_d, converted_amount: 50.to_d },
          { date: "2026-09-02", amount: 50.to_d, converted_amount: 50.to_d }
        ],
        taxes: [], discounts: [],
        service_fees: [ {
          kind: "service_fee", amount: 30.to_d, converted_amount: 30.to_d, inclusive: false,
          metadata: { "name" => "Resort fee", "basis" => "per_night" }
        } ]
      } ],
      taxes: [], service_fees: [], discounts: [], metadata: {}
    }

    snapshot = described_class.call!(financials: financials, booking: booking)
    services = snapshot.ota_financial_components.where(component_kind: "service").order(:stay_date)

    expect(services.pluck(:stay_date, :amount)).to eq([
      [ Date.new(2026, 9, 1), 15.to_d ], [ Date.new(2026, 9, 2), 15.to_d ]
    ])
    expect(services.pluck(:stable_key)).to all(include("stay_date"))
    expect(services.pluck(:basis)).to all(eq("per_night"))
    expect(snapshot.ota_financial_components.sum(:gross_effect_amount)).to eq(130.to_d)
  end


  it "preserves posted-period aggregates and stores a durable adjustment proposal for revisions" do
    hotel = create(:hotel, default_currency: "MYR")
    booking = create(:booking, hotel: hotel, check_in: Date.new(2026, 10, 1), check_out: Date.new(2026, 10, 3))
    room = create(:booking_room, booking: booking, subtotal: 100)
    build_financials = lambda do |revision, nightly_amount, cleaning_amount|
      {
        provider: "channex", channel_manager_reference: "posted-revision", provider_revision_id: revision,
        currency: "MYR", converted_currency: "MYR",
        gross_amount: nightly_amount * 2 + cleaning_amount,
        converted_gross_amount: nightly_amount * 2 + cleaning_amount,
        exchange_rate: 1.to_d, exchange_rate_source: "same_currency", conversion_rounding_amount: 0.to_d,
        rooms: [ {
          position: 1, quantity: 1, room_type: room.room_type, rate_plan: room.rate_plan,
          amount: nightly_amount * 2, converted_amount: nightly_amount * 2,
          days: [
            { date: "2026-10-01", amount: nightly_amount, converted_amount: nightly_amount },
            { date: "2026-10-02", amount: nightly_amount, converted_amount: nightly_amount }
          ], taxes: [], discounts: [],
          service_fees: [ {
            kind: "service_fee", amount: cleaning_amount, converted_amount: cleaning_amount,
            inclusive: false, metadata: { "name" => "Cleaning fee", "basis" => "per_night" }
          } ]
        } ], taxes: [], service_fees: [], discounts: [], metadata: {}
      }
    end

    first = described_class.call!(financials: build_financials.call("posted-rev-1", 50.to_d, 30.to_d), booking: booking)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    create(:folio_transaction,
      booking_folio: folio, transaction_code: room_code, amount: 65,
      transaction_type: "charge", category: "accommodation", posting_date: Date.new(2026, 10, 1),
      metadata: {
        "nightly_charge_key" => "posted-night-1", "stay_date" => "2026-10-01",
        "ota_component_stable_key" => "posted-components"
      })

    second = described_class.call!(financials: build_financials.call("posted-rev-2", 60.to_d, 40.to_d), booking: booking)

    expect(first.reload.current).to be(false)
    expect(second.reconciliation_status).to eq("rate_review_required")
    expect(second.metadata["adjustment_proposal"]).to include(
      "amount" => "15.0", "currency" => "MYR", "action" => "staff_approval_required"
    )
    expect(booking.reload.total_amount).to eq(145.to_d)
    expect(room.reload.subtotal).to eq(110.to_d)
  end


  it "prioritizes an exact source mismatch even when target values reconcile to the cent" do
    hotel = create(:hotel, default_currency: "MYR")
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.tomorrow)
    room = create(:booking_room, booking: booking)
    financials = {
      provider: "channex", channel_manager_reference: "tiny-mismatch", provider_revision_id: "tiny-1",
      currency: "MYR", converted_currency: "MYR", gross_amount: "100.0001".to_d,
      converted_gross_amount: 100.to_d, source_mismatch_amount: "0.0001".to_d,
      rooms: [ { position: 1, quantity: 1, room_type: room.room_type, rate_plan: room.rate_plan,
        amount: 100.to_d, converted_amount: 100.to_d, days: [], taxes: [], service_fees: [], discounts: [] } ],
      taxes: [], service_fees: [], discounts: [], metadata: {}
    }

    snapshot = described_class.call!(financials: financials, booking: booking)

    expect(snapshot.reconciliation_status).to eq("total_mismatch")
  end
end
