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
      expect(folio.folio_forecasted_charges.superseded.where(stay_date: business_date).count).to eq(1)
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
  end
end
