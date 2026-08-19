# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoint do
  let(:hotel) { create(:hotel) }

  describe "what an unconfigured endpoint means" do
    # Both columns default to "everything" so the endpoints that existed before
    # they did keep working untouched.
    it "serves the whole platform and every event by default" do
      endpoint = create(:webhook_endpoint)

      expect(endpoint).to be_platform_wide
      expect(endpoint).to be_all_events
    end
  end

  describe "event_types" do
    it "refuses an event nothing ever broadcasts" do
      endpoint = build(:webhook_endpoint, event_types: [ "booking_confirmed", "nonsense_event" ])

      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:event_types].join).to include("nonsense_event")
    end

    it "accepts events the app actually sends" do
      expect(build(:webhook_endpoint, event_types: [ "booking_confirmed" ])).to be_valid
    end
  end

  describe ".listening_for" do
    it "leaves out a disabled endpoint" do
      create(:webhook_endpoint, enabled: false)

      expect(described_class.listening_for("booking_confirmed", hotel_id: hotel.id)).to be_empty
    end

    it "leaves out another hotel's endpoint" do
      create(:webhook_endpoint, hotel: create(:hotel))

      expect(described_class.listening_for("booking_confirmed", hotel_id: hotel.id)).to be_empty
    end

    # Not knowing whose event this is is not a reason to hand it to a relay
    # that serves one hotel.
    it "leaves out every pinned endpoint when the event names no hotel" do
      create(:webhook_endpoint, hotel: hotel)

      expect(described_class.listening_for("booking_confirmed")).to be_empty
    end

    it "includes a platform-wide endpoint whoever the event is about" do
      endpoint = create(:webhook_endpoint)

      expect(described_class.listening_for("booking_confirmed", hotel_id: hotel.id)).to contain_exactly(endpoint)
    end

    it "includes the hotel's own endpoint" do
      endpoint = create(:webhook_endpoint, hotel: hotel)

      expect(described_class.listening_for("booking_confirmed", hotel_id: hotel.id)).to contain_exactly(endpoint)
    end

    it "leaves out an endpoint that asked for other events" do
      create(:webhook_endpoint, event_types: [ "complaint_resolved" ])

      expect(described_class.listening_for("booking_confirmed")).to be_empty
    end

    it "includes an endpoint that named this event among others" do
      endpoint = create(:webhook_endpoint, event_types: [ "complaint_resolved", "booking_confirmed" ])

      expect(described_class.listening_for("booking_confirmed")).to contain_exactly(endpoint)
    end
  end
end
