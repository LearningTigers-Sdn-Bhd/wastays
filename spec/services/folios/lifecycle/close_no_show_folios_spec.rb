# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::CloseNoShowFolios do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      status: "no_show_detected",
      no_show_detected_business_date: hotel.current_business_date
    )
  end

  it "supersedes forecasts, closes zero-balance folios, and reports non-zero folios" do
    settled_folio = create(:booking_folio, booking: booking, hotel: hotel)
    unsettled_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    settled_forecast = create(:folio_forecasted_charge, booking_folio: settled_folio)
    unsettled_forecast = create(:folio_forecasted_charge, booking_folio: unsettled_folio)
    create(:folio_transaction, booking_folio: unsettled_folio, amount: 75)

    expect {
      @result = described_class.call(
        booking: booking,
        user: user,
        business_date: hotel.current_business_date
      )
    }.to change(FolioOperationLog.where(operation_type: "close_folio"), :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "no_show_folio_closed"), :count).by(1)

    expect(@result).to be_success
    expect(@result.closed_folios).to contain_exactly(settled_folio)
    expect(@result.skipped_folios.sole).to have_attributes(folio: unsettled_folio, balance: 75.to_d)
    expect(settled_folio.reload).to be_closed
    expect(unsettled_folio.reload).to be_open
    expect(settled_forecast.reload.status).to eq("superseded")
    expect(unsettled_forecast.reload.status).to eq("superseded")
  end
end
