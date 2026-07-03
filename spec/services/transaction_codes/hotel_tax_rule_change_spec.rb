# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCodes::HotelTaxRuleChange do
  it "reports eligible ROOM forecast impact under the open-folio policy" do
    hotel = create(:hotel)
    hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    folio = create(:booking_folio, hotel:, booking: create(:booking, hotel:))
    create(:folio_forecasted_charge, booking_folio: folio, amount: 125)

    preview = described_class.preview(transaction_code: code, proposed_keys: [ "primary:sst_tax" ])

    expect(preview).to have_attributes(
      changed?: true,
      forecast_policy: "open_folio_forecasts",
      forecast_count: 1,
      forecast_amount: 125.to_d
    )
  end

  it "does not report forecast reconciliation for ROOM under new-bookings-only" do
    hotel = create(:hotel)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    folio = create(:booking_folio, hotel:, booking: create(:booking, hotel:))
    create(:folio_forecasted_charge, booking_folio: folio)

    preview = described_class.preview(transaction_code: code, proposed_keys: [ "primary:sst_tax" ])

    expect(preview).to have_attributes(
      forecast_policy: "new_bookings_only",
      forecast_count: 0,
      forecast_amount: 0.to_d
    )
  end

  it "treats non-ROOM codes as future manual postings without forecast reconciliation" do
    hotel = create(:hotel)
    code = create(:transaction_code, hotel:, kind: "charge")

    preview = described_class.preview(transaction_code: code, proposed_keys: [ "primary:sst_tax" ])

    expect(preview).to have_attributes(
      forecast_policy: "future_manual_postings",
      forecast_count: 0,
      forecast_amount: 0.to_d
    )
  end
end
