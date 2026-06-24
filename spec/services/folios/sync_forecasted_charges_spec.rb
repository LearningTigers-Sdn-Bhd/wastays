# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::SyncForecastedCharges do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 2.days) }
  let!(:booking_room) { create(:booking_room, booking: booking, subtotal: 200.0) }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }

  describe ".call" do
    it "does not recreate pending forecasts for nights already posted by night audit" do
      Folios::GenerateForecastedCharges.call(booking_folio: folio)
      forecast = folio.folio_forecasted_charges.forecast.find_by!(stay_date: business_date, charge_kind: "accommodation")
      transaction = create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: 100.0,
        posting_date: business_date,
        metadata: {
          nightly_charge_key: [ booking.id, business_date.iso8601, "accommodation", booking_room.id ].join(":"),
          stay_date: business_date.iso8601
        }
      )
      forecast.actualize!(transaction: transaction)

      described_class.call(booking_folio: folio)

      expect(folio.folio_forecasted_charges.forecast.where(stay_date: business_date)).to be_none
      expect(folio.folio_forecasted_charges.forecast.where(stay_date: business_date + 1.day).count).to eq(1)
      expect(forecast.reload.status).to eq("actualized")
    end

    it "supersedes pending forecasts for dates already posted by catch-up charges" do
      Folios::GenerateForecastedCharges.call(booking_folio: folio)
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: 100.0,
        posting_date: business_date,
        metadata: {
          catch_up_key: [ "catch_up", booking.id, business_date.iso8601, "accommodation", booking_room.id ].join(":"),
          stay_date: business_date.iso8601
        }
      )

      described_class.call(booking_folio: folio)

      expect(folio.folio_forecasted_charges.forecast.where(stay_date: business_date)).to be_none
      expect(folio.folio_forecasted_charges.actualized.where(stay_date: business_date).count).to eq(1)
      expect(folio.folio_forecasted_charges.forecast.where(stay_date: business_date + 1.day).count).to eq(1)
    end

    it "does not treat one same-amount room charge as posted for every matching forecast" do
      second_room = create(:booking_room, booking: booking, subtotal: 200.0)
      Folios::GenerateForecastedCharges.call(booking_folio: folio)
      create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: 100.0,
        posting_date: business_date,
        metadata: {
          nightly_charge_key: [ booking.id, business_date.iso8601, "accommodation", booking_room.id ].join(":"),
          stay_date: business_date.iso8601
        }
      )

      described_class.call(booking_folio: folio)

      pending_today = folio.folio_forecasted_charges.forecast.where(stay_date: business_date, charge_kind: "accommodation")
      expect(pending_today.pluck(:identity)).to contain_exactly(second_room.id.to_s)
    end

    it "does not recreate rows for already actualized forecasts without modern transaction metadata" do
      Folios::GenerateForecastedCharges.call(booking_folio: folio)
      folio.folio_forecasted_charges.forecast.each do |forecast|
        transaction = create(
          :folio_transaction,
          booking_folio: folio,
          transaction_type: :charge,
          category: forecast.charge_kind,
          amount: forecast.amount,
          posting_date: forecast.stay_date,
          metadata: { stay_date: forecast.stay_date.iso8601 }
        )
        forecast.actualize!(transaction: transaction)
      end

      expect {
        described_class.call(booking_folio: folio)
      }.not_to change { folio.folio_forecasted_charges.forecast.count }
    end

    it "replaces active forecasts when the expected amount changes" do
      Folios::GenerateForecastedCharges.call(booking_folio: folio)
      booking_room.update!(subtotal: 300.0)

      described_class.call(booking_folio: folio)

      forecasts = folio.folio_forecasted_charges.forecast.order(:stay_date)
      expect(forecasts.map(&:amount)).to eq([ 150.0, 150.0 ])
      expect(folio.folio_forecasted_charges.superseded.count).to eq(2)
    end

    it "supersedes active forecasts when normal stay forecasts no longer apply" do
      Folios::GenerateForecastedCharges.call(booking_folio: folio)
      booking.update_column(:status, "no_show")

      described_class.call(booking_folio: folio)

      expect(folio.folio_forecasted_charges.forecast).to be_none
      expect(folio.folio_forecasted_charges.superseded.count).to eq(2)
    end

    it "creates ROOM forecasts only on the routed target folio" do
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

      described_class.call(booking_folio: folio)

      expect(folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")).to be_none
      expect(company_folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation").count).to eq(2)
    end

    it "routes SST and TTX forecasts independently by their transaction codes" do
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
      ttx_code = hotel.transaction_codes.find_by!(system_key: "tourism_tax")
      booking.update!(tax_posting_snapshot: {
        business_date.iso8601 => [
          { "name" => "SST", "amount" => "8.00", "type" => "sst", "transaction_code_id" => sst_code.id },
          { "name" => "Tourism Tax", "amount" => "10.00", "type" => "tourism_tax", "transaction_code_id" => ttx_code.id }
        ],
        (business_date + 1.day).iso8601 => [
          { "name" => "SST", "amount" => "8.00", "type" => "sst", "transaction_code_id" => sst_code.id },
          { "name" => "Tourism Tax", "amount" => "10.00", "type" => "tourism_tax", "transaction_code_id" => ttx_code.id }
        ]
      })
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: sst_code, target_folio: company_folio)
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: ttx_code, target_folio: folio)

      described_class.call(booking_folio: folio)

      expect(company_folio.folio_forecasted_charges.forecast.where(charge_kind: "tax").pluck(:identity)).to contain_exactly("sst:0", "sst:0")
      expect(folio.folio_forecasted_charges.forecast.where(charge_kind: "tax").pluck(:identity)).to contain_exactly("tourism_tax:1", "tourism_tax:1")
    end

    it "places attached tax forecasts with the routed parent folio" do
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
      booking.update!(tax_posting_snapshot: {
        business_date.iso8601 => [
          {
            "name" => "SST",
            "amount" => "8.00",
            "type" => "sst",
            "transaction_code_id" => sst_code.id,
            "source_transaction_code_id" => room_code.id
          }
        ]
      })
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

      described_class.call(booking_folio: folio)

      expect(company_folio.folio_forecasted_charges.forecast.where(stay_date: business_date).pluck(:charge_kind)).to contain_exactly("accommodation", "tax")
      expect(folio.folio_forecasted_charges.forecast.where(stay_date: business_date)).to be_none
    end

    it "supersedes future forecasts on the old folio when routing changes" do
      described_class.call(booking_folio: folio)
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

      described_class.call(booking_folio: folio)

      expect(folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")).to be_none
      expect(folio.folio_forecasted_charges.superseded.where(charge_kind: "accommodation").count).to eq(2)
      expect(company_folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation").count).to eq(2)
    end

    it "does not move or supersede actualized forecasts when routing changes" do
      described_class.call(booking_folio: folio)
      forecast = folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation").first
      transaction = create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: forecast.amount)
      forecast.actualize!(transaction: transaction)
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

      described_class.call(booking_folio: folio)

      expect(forecast.reload.status).to eq("actualized")
      expect(forecast.booking_folio).to eq(folio)
      expect(transaction.reload.booking_folio).to eq(folio)
    end
  end
end
