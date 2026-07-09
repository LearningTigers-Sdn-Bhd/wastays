# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCodes::ApplyHotelTaxRuleChange do
  it "requires a reason" do
    transaction_code = create(:transaction_code)

    result = described_class.call(
      transaction_code: transaction_code,
      actor: nil,
      attributes: {},
      proposed_keys: [ "primary:sst_tax" ],
      reason: " ",
      freshness_token: nil
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Reason is required for a hotel-wide tax inclusion change.")
  end

  it "rejects stale freshness tokens before changing tax rules" do
    transaction_code = create(:transaction_code)
    token = TransactionCodes::HotelTaxRuleChange.preview(transaction_code: transaction_code, proposed_keys: [ "primary:sst_tax" ]).freshness_token
    transaction_code.touch

    result = described_class.call(
      transaction_code: transaction_code,
      actor: nil,
      attributes: { name: "Updated" },
      proposed_keys: [ "primary:sst_tax" ],
      reason: "Apply SST",
      freshness_token: token
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Transaction code tax rules changed after this review. Review the latest configuration and try again.")
    expect(transaction_code.reload.name).not_to eq("Updated")
    expect(transaction_code.transaction_code_taxes.reload).to be_empty
  end

  it "replaces tax rules, updates attributes, and records audit metadata" do
    hotel = create(:hotel)
    transaction_code = create(:transaction_code, hotel: hotel, code: "FOOD", name: "Food", kind: "charge")
    actor = create(:user, account: hotel.account)
    custom_tax = create(:hotel_tax, hotel: hotel, name: "Heritage Fee", code: "HERITAGE")
    create(:transaction_code_tax, transaction_code: transaction_code, hotel_tax: nil, primary_tax_key: "tourism_tax")
    proposed_keys = [ "primary:sst_tax", "hotel_tax:#{custom_tax.id}" ]
    preview = TransactionCodes::HotelTaxRuleChange.preview(transaction_code: transaction_code, proposed_keys: proposed_keys)
    allow(Folios::RefreshOpenForecastsFromRoomRevenueRules).to receive(:call)

    expect {
      @result = described_class.call(
        transaction_code: transaction_code,
        actor: actor,
        attributes: { name: "Food Revenue" },
        proposed_keys: proposed_keys,
        reason: "Align tax setup",
        freshness_token: preview.freshness_token
      )
    }.to change(FinancialAuditEvent.where(event_type: "hotel_tax_rules_changed"), :count).by(1)

    result = @result
    audit = FinancialAuditEvent.where(event_type: "hotel_tax_rules_changed").order(:id).last
    expect(result).to be_success
    expect(transaction_code.reload.name).to eq("Food Revenue")
    expect(transaction_code.transaction_code_taxes.reload.map(&:tax_rule_key)).to match_array(proposed_keys)
    expect(Folios::RefreshOpenForecastsFromRoomRevenueRules).not_to have_received(:call)
    expect(audit).to have_attributes(hotel: hotel, actor: actor, source: "transaction_codes", reason: "Align tax setup")
    expect(audit.metadata).to include(
      "transaction_code_id" => transaction_code.id,
      "transaction_code" => "FOOD",
      "before_tax_rule_keys" => [ "primary:tourism_tax" ],
      "after_tax_rule_keys" => proposed_keys.sort,
      "forecast_policy" => "future_manual_postings",
      "forecasts_changed" => 0
    )
  end

  it "refreshes open forecasts when room revenue uses the open-folio policy" do
    hotel = create(:hotel)
    hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
    transaction_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    actor = create(:user, account: hotel.account)
    preview = TransactionCodes::HotelTaxRuleChange.preview(transaction_code: transaction_code, proposed_keys: [ "primary:sst_tax" ])
    refresh_result = OpenStruct.new(forecasts_changed: 3)
    allow(Folios::RefreshOpenForecastsFromRoomRevenueRules).to receive(:call).and_return(refresh_result)
    allow(FinancialControls::AuditEventRecorder).to receive(:call!)

    result = described_class.call(
      transaction_code: transaction_code,
      actor: actor,
      attributes: {},
      proposed_keys: [ "primary:sst_tax" ],
      reason: "Refresh open forecasts",
      freshness_token: preview.freshness_token
    )

    expect(result).to be_success
    expect(result.refresh_result).to eq(refresh_result)
    expect(Folios::RefreshOpenForecastsFromRoomRevenueRules).to have_received(:call).with(hotel: hotel, actor: actor)
    expect(FinancialControls::AuditEventRecorder).to have_received(:call!).with(hash_including(
      hotel: hotel,
      event_type: "hotel_tax_rules_changed",
      metadata: hash_including(forecasts_changed: 3, forecast_policy: "open_folio_forecasts")
    ))
  end
end
