require "rails_helper"

RSpec.describe Folios::GenerateForecastedCharges do
  describe ".call" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days) }
    let!(:booking_room) { create(:booking_room, booking: booking, subtotal: 200.0) }
    let(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }

    it "creates forecast charges for each night of the stay" do
      described_class.call(booking_folio: folio)

      forecasts = folio.folio_forecasted_charges.forecast.order(:stay_date, :charge_kind)
      expect(forecasts.count).to eq(2) # 1 accommodation charge per night

      expect(forecasts[0].attributes).to include(
        "stay_date" => Date.current,
        "charge_kind" => "accommodation",
        "identity" => booking_room.id.to_s,
        "amount" => 100.0,
        "description" => "Room Charge - #{Date.current}"
      )

      expect(forecasts[1].attributes).to include(
        "stay_date" => Date.current + 1.day,
        "charge_kind" => "accommodation",
        "identity" => booking_room.id.to_s,
        "amount" => 100.0,
        "description" => "Room Charge - #{Date.current + 1.day}"
      )
    end

    it "creates tax forecast charges when tax_lines are present" do
      booking.update!(tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])

      described_class.call(booking_folio: folio)

      tax_forecasts = folio.folio_forecasted_charges.forecast.where(charge_kind: "tax")
      expect(tax_forecasts.count).to eq(2) # 1 tax line per night
    end

    it "creates tax forecasts from tax_snapshot when available" do
      booking.update!(
        tax_lines: [],
        tax_posting_snapshot: {
          Date.current.iso8601 => [ { "name" => "SST", "amount" => "10.00", "type" => "sst", "source" => "hotel_sst" } ],
          (Date.current + 1.day).iso8601 => [ { "name" => "SST", "amount" => "10.00", "type" => "sst", "source" => "hotel_sst" } ]
        }
      )

      described_class.call(booking_folio: folio)

      tax_forecasts = folio.folio_forecasted_charges.forecast.where(charge_kind: "tax").order(:stay_date)
      expect(tax_forecasts.count).to eq(2)
      expect(tax_forecasts.map(&:amount)).to all(eq(10.0))
    end

    it "creates new forecasts from ROOM transaction code tax rule snapshots" do
      hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
      snapshot = Bookings::BuildFinancialSnapshot.new(
        hotel: hotel,
        check_in: booking.check_in,
        check_out: booking.check_out,
        guest_country: "Singapore",
        room_items: [
          {
            quantity: 1,
            nightly_rate_snapshot: booking_room.nightly_rate_snapshot.presence || {
              Date.current.iso8601 => { "price" => "100.00" },
              (Date.current + 1.day).iso8601 => { "price" => "100.00" }
            }
          }
        ]
      ).call
      booking.update!(guest_country: "Singapore", tax_lines: snapshot.tax_lines, tax_posting_snapshot: snapshot.tax_posting_snapshot)

      described_class.call(booking_folio: folio)

      tax_forecasts = folio.folio_forecasted_charges.forecast.where(charge_kind: "tax").order(:stay_date, :identity)
      expect(tax_forecasts.count).to eq(4)
      expect(tax_forecasts.map(&:description)).to include("Tax: SST 8% - #{Date.current}", "Tax: Tourism Tax - #{Date.current}")
      expect(tax_forecasts.map(&:amount)).to include(8.0, 10.0)
    end

    it "does not recalculate existing unposted forecasts when rules change under new-bookings-only policy" do
      booking.update!(
        tax_posting_snapshot: {
          Date.current.iso8601 => [ { "name" => "Original Tax", "amount" => "5.00", "type" => "original", "source" => "legacy" } ]
        }
      )
      described_class.call(booking_folio: folio)
      original_tax_forecast = folio.folio_forecasted_charges.forecast.find_by!(charge_kind: "tax")
      original_snapshot = booking.reload.tax_posting_snapshot

      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

      expect(booking.reload.tax_posting_snapshot).to eq(original_snapshot)
      expect(folio.folio_forecasted_charges.forecast.count).to eq(3)
      expect(original_tax_forecast.reload.description).to eq("Tax: Original Tax - #{Date.current}")
      expect(original_tax_forecast.amount).to eq(5.0)
    end

    it "does not create forecasts for the checkout day" do
      booking.update!(check_out: Date.current + 1.day)

      described_class.call(booking_folio: folio)

      expect(folio.folio_forecasted_charges.count).to eq(1)
      expect(folio.folio_forecasted_charges.forecast.first.stay_date).to eq(Date.current)
    end

    it "is idempotent" do
      described_class.call(booking_folio: folio)

      expect {
        described_class.call(booking_folio: folio)
      }.not_to change { folio.folio_forecasted_charges.count }
    end

    it "uses nightly_rate_snapshot when available" do
      booking_room.update!(
        nightly_rate_snapshot: {
          Date.current.iso8601 => { "price" => "150.00", "source" => "room_rate" },
          (Date.current + 1.day).iso8601 => { "price" => "200.00", "source" => "room_rate" }
        }
      )

      described_class.call(booking_folio: folio)

      forecasts = folio.folio_forecasted_charges.forecast.order(:stay_date)
      expect(forecasts[0].amount).to eq(150.0)
      expect(forecasts[1].amount).to eq(200.0)
    end

    it "allocates rounding remainder to the final night" do
      booking.update!(check_in: Date.current, check_out: Date.current + 3.days)
      booking_room.update!(subtotal: 100.0)

      described_class.call(booking_folio: folio)

      forecasts = folio.folio_forecasted_charges.forecast.order(:stay_date)
      expect(forecasts.count).to eq(3)
      expect(forecasts[0].amount).to eq(33.33)
      expect(forecasts[1].amount).to eq(33.33)
      expect(forecasts[2].amount).to eq(33.34)
    end

    context "with multiple rooms" do
      let!(:booking_room2) { create(:booking_room, booking: booking, subtotal: 100.0) }

      it "creates separate forecasts per room" do
        described_class.call(booking_folio: folio)

        accommodation_forecasts = folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")
        expect(accommodation_forecasts.count).to eq(4) # 2 rooms x 2 nights
      end
    end
  end
end
