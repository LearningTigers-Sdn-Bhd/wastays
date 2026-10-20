# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::RerouteScheduledExtras do
  let(:booking) { create(:booking) }
  let(:hotel) { booking.hotel }
  let(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel, is_primary: true) }
  let(:agent_account) { create(:hotel_corporate_account, hotel: hotel) }
  let(:agent_folio) { create(:booking_folio, booking: booking, hotel: hotel, folio_type: "external", payer_type: "company", hotel_corporate_account: agent_account) }
  let(:extra_charge) { create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: true) }
  let(:extra_code) { extra_charge.transaction_code }

  it "moves scheduled extra charges and their tax lines to the routed target folio" do
    create(:folio_routing_rule, booking: booking, transaction_code: extra_code, target_folio: agent_folio, active: true)

    parent_forecast = create(:folio_forecasted_charge,
      booking_folio: guest_folio,
      source_booking: booking,
      charge_kind: "extra_charge",
      status: "forecast",
      stay_date: Date.current,
      amount: 50.0,
      metadata: { "transaction_code_id" => extra_code.id, "extra_charge_id" => extra_charge.id })

    tax_forecast = create(:folio_forecasted_charge,
      booking_folio: guest_folio,
      source_booking: booking,
      charge_kind: "extra_charge_tax",
      status: "forecast",
      stay_date: Date.current,
      amount: 4.0,
      metadata: { "parent_forecast_id" => parent_forecast.id, "transaction_code_id" => extra_code.id })

    described_class.call(booking: booking)

    expect(parent_forecast.reload.status).to eq("superseded")
    expect(tax_forecast.reload.status).to eq("superseded")

    agent_forecasts = agent_folio.folio_forecasted_charges.forecast.order(:id).to_a
    expect(agent_forecasts.size).to eq(2)

    new_parent = agent_forecasts.first
    expect(new_parent).to have_attributes(
      charge_kind: "extra_charge",
      amount: 50.0.to_d,
      source_booking_id: booking.id
    )

    new_tax = agent_forecasts.second
    expect(new_tax).to have_attributes(
      charge_kind: "extra_charge_tax",
      amount: 4.0.to_d,
      source_booking_id: booking.id
    )
    expect(new_tax.metadata["parent_forecast_id"]).to eq(new_parent.id)
  end

  it "leaves scheduled extras on their current folio when no routing rule applies" do
    other_extra = create(:hotel_extra_charge, hotel: hotel, bill_to_travel_agent: false)
    other_code = other_extra.transaction_code

    forecast = create(:folio_forecasted_charge,
      booking_folio: guest_folio,
      source_booking: booking,
      charge_kind: "extra_charge",
      status: "forecast",
      stay_date: Date.current,
      amount: 30.0,
      metadata: { "transaction_code_id" => other_code.id, "extra_charge_id" => other_extra.id })

    described_class.call(booking: booking)

    expect(forecast.reload.status).to eq("forecast")
    expect(agent_folio.folio_forecasted_charges).to be_empty
  end
end
