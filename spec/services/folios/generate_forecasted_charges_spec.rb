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
