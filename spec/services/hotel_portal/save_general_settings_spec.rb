# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::SaveGeneralSettings, type: :service do
  let(:hotel) { create(:hotel) }
  let!(:property_policy) { create(:property_policy, hotel: hotel) }

  describe ".call" do
    let(:permitted_params) do
      {
        default_currency: "USD",
        time_zone: "Asia/Kuala_Lumpur",
        geolocation_enabled: true
      }
    end

    let(:property_policy_params) do
      {
        check_in_time: "14:00",
        check_out_time: "12:00"
      }
    end

    it "updates the hotel details" do
      result = described_class.call(hotel, permitted_params, {}, false)
      expect(result).to be true
      expect(hotel.reload.default_currency).to eq("USD")
      expect(hotel.reload.time_zone).to eq("Asia/Kuala_Lumpur")
      expect(hotel.reload.geolocation_enabled).to be true
    end

    it "updates the property policy when requested" do
      result = described_class.call(hotel, {}, property_policy_params, true)
      expect(result).to be true
      expect(hotel.reload.property_policy.check_in_time).to eq("14:00")
      expect(hotel.reload.property_policy.check_out_time).to eq("12:00")
    end

    context "when transaction fails" do
      it "returns false and rolls back changes" do
        allow(hotel).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(hotel))
        result = described_class.call(hotel, permitted_params, {}, false)
        expect(result).to be false
      end
    end
  end
end
