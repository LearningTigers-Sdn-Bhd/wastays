# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::SaveConciergeSettings, type: :service do
  let(:hotel) do
    create(:hotel, guest_chat_enabled: true, concierge_refund_requests_enabled: false,
      concierge_menu_style: "interactive")
  end

  describe ".call" do
    it "updates the submitted Concierge settings" do
      result = described_class.call(hotel, {
        guest_chat_enabled: "0",
        concierge_refund_requests_enabled: "1",
        concierge_menu_style: "fancy"
      })

      expect(result).to be(true)
      expect(hotel.reload).to have_attributes(
        guest_chat_enabled: false,
        concierge_refund_requests_enabled: true,
        concierge_menu_style: "fancy"
      )
    end

    it "preserves a setting that the submitted section did not include" do
      expect(described_class.call(hotel, { concierge_menu_style: "fancy" })).to be(true)

      expect(hotel.reload.guest_chat_enabled).to be(true)
      expect(hotel.concierge_refund_requests_enabled).to be(false)
      expect(hotel.concierge_menu_style).to eq("fancy")
    end

    it "returns false for an invalid menu style" do
      expect(described_class.call(hotel, { concierge_menu_style: "plain" })).to be(false)
      expect(hotel.errors[:concierge_menu_style]).to be_present
    end
  end
end
