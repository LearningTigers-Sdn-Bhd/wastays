# frozen_string_literal: true

require "rails_helper"

RSpec.describe Checkouts::ProcessBookingCheckout do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_out: Date.current) }
  let(:user) { create(:user, account: hotel.account) }
  let(:timestamp) { Time.zone.local(Date.current.year, Date.current.month, Date.current.day, 10, 0, 0) }
  let(:folio_action_params) { { "1" => { action: "close" } } }
  let(:posting_date) { Date.new(2026, 7, 9) }

  it "requires a timestamp for checkout-required bookings" do
    booking.update_columns(status: "checkout_required")

    result = call_service(timestamp: nil)

    expect(result).not_to be_success
    expect(result.error).to eq("Check-out date and time can't be blank.")
  end

  it "short-circuits when early departure processing fails" do
    booking.update!(check_out: Date.current + 2.days)
    allow(hotel).to receive(:business_date_for).and_return(Date.current)
    allow(Bookings::ProcessEarlyDeparture).to receive(:call).and_return(OpenStruct.new(success?: false, error: "Early departure invalid"))
    allow(Folios::Checkout::ProcessCheckoutActions).to receive(:call)

    result = call_service

    expect(result).not_to be_success
    expect(result.error).to eq("Early departure invalid")
    expect(Folios::Checkout::ProcessCheckoutActions).not_to have_received(:call)
  end

  it "does not process checkout-required bookings as early departures" do
    booking.update_columns(status: "checkout_required")
    booking.update!(check_out: Date.current + 2.days)
    settlement = OpenStruct.new(success?: true, exception_folio_ids: [], direct_bill_folio_ids: [])
    transition = instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: true))
    allow(hotel).to receive(:business_date_for).and_return(Date.current)
    allow(Bookings::ProcessEarlyDeparture).to receive(:call)
    allow(Folios::Checkout::ProcessCheckoutActions).to receive(:call).and_return(settlement)
    allow(Bookings::TransitionStatus).to receive(:new).and_return(transition)

    result = call_service

    expect(result).to be_success
    expect(Bookings::ProcessEarlyDeparture).not_to have_received(:call)
    expect(transition).to have_received(:call)
  end

  it "short-circuits when folio actions fail" do
    allow(Folios::Checkout::ProcessCheckoutActions).to receive(:call).and_return(OpenStruct.new(success?: false, error: "Settle folio first"))
    allow(Bookings::TransitionStatus).to receive(:new)

    result = call_service

    expect(result).not_to be_success
    expect(result.error).to eq("Settle folio first")
    expect(Bookings::TransitionStatus).not_to have_received(:new)
  end

  it "transitions to completed with checkout folio options" do
    settlement = OpenStruct.new(success?: true, exception_folio_ids: [ 11 ], direct_bill_folio_ids: [ 22 ])
    transition = instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: true))
    allow(Folios::Checkout::ProcessCheckoutActions).to receive(:call).and_return(settlement)
    allow(Bookings::TransitionStatus).to receive(:new).and_return(transition)

    result = call_service(checkout_options: { note: "front desk" }, security_deposit_options: { release_security_deposit: true })

    expect(result).to be_success
    expect(Folios::Checkout::ProcessCheckoutActions).to have_received(:call).with(
      booking: booking,
      hotel: hotel,
      user: user,
      action_params: folio_action_params,
      posting_date: posting_date,
      options: { note: "front desk" }
    )
    expect(Bookings::TransitionStatus).to have_received(:new).with(
      booking: booking,
      status: "completed",
      timestamp: timestamp,
      user: user,
      options: {
        defer_side_effects: true,
        exception_folio_ids: [ 11 ],
        direct_bill_folio_ids: [ 22 ],
        note: "front desk",
        release_security_deposit: true
      }
    )
    expect(transition).to have_received(:call)
    expect(result.booking).to eq(booking)
  end

  it "returns transition failures" do
    allow(Folios::Checkout::ProcessCheckoutActions).to receive(:call).and_return(OpenStruct.new(success?: true, exception_folio_ids: [], direct_bill_folio_ids: []))
    allow(Bookings::TransitionStatus).to receive(:new).and_return(
      instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: false, error: "Cannot complete"))
    )

    result = call_service

    expect(result).not_to be_success
    expect(result.error).to eq("Cannot complete")
  end

  def call_service(timestamp: self.timestamp, checkout_options: {}, security_deposit_options: {})
    described_class.call(
      booking: booking,
      hotel: hotel,
      user: user,
      timestamp: timestamp,
      folio_action_params: folio_action_params,
      posting_date: posting_date,
      checkout_options: checkout_options,
      security_deposit_options: security_deposit_options
    )
  end
end
