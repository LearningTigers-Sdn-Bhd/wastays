# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::MoveForecast do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:source_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:target_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }

  it "moves an active forecast to another open folio" do
    forecast = create(:folio_forecasted_charge, booking_folio: source_folio, amount: 370, stay_date: Date.current)

    result = described_class.call(forecast: forecast, target_folio: target_folio, user: user, reason: "Company pays room")

    expect(result).to be_success
    expect(forecast.reload.booking_folio).to eq(target_folio)
    expect(FolioOperationLog.last.operation_type).to eq("move_forecast")
  end
end
