# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::PolicyPresenter do
  let(:hotel) { create(:hotel) }

  before do
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00")
    create(:room_type, hotel: hotel, smoking_allowed: false, pets_allowed: true)
    create(:hotel_reservation_policy, hotel: hotel, policy_type: "late_checkout", pricing_type: "fixed",
           rate_value: 100, allow_amount_override: false, description: "Ask the day before.")
    create(:hotel_reservation_policy, :no_show, hotel: hotel)
    create(:hotel_reservation_policy, hotel: hotel, policy_type: "early_departure", active: false, position: 3)
  end

  def facts(presenter) = presenter.glance.to_h { |fact| [ fact.label, fact.value ] }

  context "without a stay" do
    subject(:presenter) { described_class.new(hotel: hotel, documents: []) }

    it "gives the times, the charges, and the room rules at a glance" do
      expect(facts(presenter)).to eq(
        "Check-in from" => "15:00", "Check-out by" => "12:00",
        "Smoking" => "Not allowed in rooms", "Pets" => "Allowed in some rooms"
      )
    end

    it "lists every change the property charges for, and skips one it turned off" do
      expect(presenter.changes_title).to eq("Changes and cancellation")
      expect(presenter.changes.map(&:label)).to eq([ "No-show", "Late checkout" ])
      expect(presenter.changes.last).to have_attributes(charge: "#{hotel.default_currency} 100.00", note: "Ask the day before.")
    end

    it "tells a guest to ask when staff set the amount by hand" do
      hotel.hotel_reservation_policies.find_by(policy_type: "late_checkout").update!(pricing_type: "manual", rate_value: nil)

      expect(presenter.changes.last.charge).to eq("Ask the front desk")
    end
  end

  context "with an in-house stay" do
    let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_out: Date.new(2026, 9, 26)) }

    subject(:presenter) { described_class.new(hotel: hotel, documents: [], booking: booking) }

    it "turns the glance to leaving: the check-out day and the late check-out charge" do
      expect(facts(presenter)).to include("Check-out by" => "12:00 on Sat, 26 Sep",
                                          "Late check-out" => "#{hotel.default_currency} 100.00")
      expect(facts(presenter)).not_to include("Check-in from", "Cancellation")
    end

    it "keeps only the changes a guest can still make" do
      expect(presenter.changes_title).to eq("Changes to your stay")
      expect(presenter.changes.map(&:label)).to eq([ "Late checkout" ])
    end
  end

  it "picks an icon from the policy card a document belongs to" do
    presenter = described_class.new(hotel: hotel, documents: [])

    expect(presenter.document_icon(build(:hotel_knowledge_document, metadata: { "policy_key" => "house_rules" }))).to eq("house")
    expect(presenter.document_icon(build(:hotel_knowledge_document, metadata: {}))).to eq("file-text")
  end
end
