# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::ArrivalPresenter do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "confirmed") }
  subject { described_class.new(booking, hotel) }

  describe "#arrival_marker" do
    it "leaves a guest who is still on the way unmarked" do
      expect(subject.arrival_marker).to be_nil
    end

    it "marks a guest who has arrived" do
      booking.update!(checked_in_at: Time.current)

      expect(subject.arrival_marker).to include(label: "Arrived", icon: "check")
      expect(subject.arrival_marker[:tone]).to include("text-success")
    end

    it "marks a missed arrival that night audit found" do
      booking.update_columns(status: "no_show_detected")

      expect(subject.arrival_marker).to include(label: "Missed", icon: "triangle-alert")
      expect(subject.arrival_marker[:tone]).to include("text-warning")
    end

    it "prefers the missed mark over the arrived one" do
      booking.update!(checked_in_at: Time.current)
      booking.update_columns(status: "no_show_detected")

      expect(subject.arrival_marker[:label]).to eq("Missed")
    end
  end
end
