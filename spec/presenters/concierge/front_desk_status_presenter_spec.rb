# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::FrontDeskStatusPresenter do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }

  def status_at(clock)
    described_class.new(hotel: hotel.reload, now: Time.find_zone("Kuala Lumpur").parse(clock))
  end

  context "when the hotel never filled the page" do
    it "renders nothing and stays closed" do
      status = status_at("2026-09-08 10:00")

      expect(status.render?).to be(false)
      expect(status.open?).to be(false)
      expect(status.headline).to be_nil
    end
  end

  context "when the desk is open 24 hours" do
    before { create(:hotel_guest_contact, hotel: hotel, front_desk_open_24h: true) }

    it "is always open" do
      status = status_at("2026-09-08 03:00")

      expect(status.open?).to be(true)
      expect(status.always_open?).to be(true)
      expect(status.headline).to eq("Front desk is open 24 hours")
      expect(status.detail).to be_nil
    end
  end

  context "with a normal window of 07:00 to 23:00" do
    before { create(:hotel_guest_contact, :with_hours, hotel: hotel) }

    it "is open inside the window" do
      status = status_at("2026-09-08 10:00")

      expect(status.open?).to be(true)
      expect(status.headline).to eq("Front desk is open until 11:00 PM")
    end

    it "is closed before it opens" do
      status = status_at("2026-09-08 03:00")

      expect(status.open?).to be(false)
      expect(status.headline).to eq("Front desk is closed")
      expect(status.detail).to eq("Opens again at 7:00 AM")
    end

    it "is closed on the closing minute" do
      expect(status_at("2026-09-08 23:00").open?).to be(false)
    end
  end

  context "with a window that crosses midnight, 18:00 to 02:00" do
    before { create(:hotel_guest_contact, :overnight, hotel: hotel) }

    it "is open at 01:00" do
      expect(status_at("2026-09-08 01:00").open?).to be(true)
    end

    it "is closed at 03:00" do
      status = status_at("2026-09-08 03:00")

      expect(status.open?).to be(false)
      expect(status.detail).to eq("Opens again at 6:00 PM")
    end
  end

  describe "the hotel time zone" do
    before { create(:hotel_guest_contact, :with_hours, hotel: hotel) }

    it "reads the clock where the hotel stands, not where the server does" do
      # 02:00 UTC is 10:00 in Kuala Lumpur, inside the 07:00-23:00 window.
      status = described_class.new(hotel: hotel.reload, now: Time.utc(2026, 9, 8, 2, 0))

      expect(status.open?).to be(true)
    end
  end

  describe "#handover_message" do
    it "promises a person while the desk is open" do
      create(:hotel_guest_contact, :with_hours, hotel: hotel)

      expect(status_at("2026-09-08 10:00").handover_message).to eq(described_class::DEFAULT_HANDOVER)
    end

    it "names the duty manager and the opening time after hours" do
      create(:hotel_guest_contact, :with_hours, hotel: hotel, duty_manager_phone: "+60 12 987 6543")

      message = status_at("2026-09-08 03:00").handover_message

      expect(message).to include("The front desk is closed.")
      expect(message).to include("+60 12 987 6543")
      expect(message).to include("7:00 AM")
    end

    it "prefers the message the hotel wrote" do
      create(:hotel_guest_contact, :with_hours, hotel: hotel, after_hours_message: "Ring the night bell.")

      expect(status_at("2026-09-08 03:00").handover_message).to eq("Ring the night bell.")
    end
  end
end
