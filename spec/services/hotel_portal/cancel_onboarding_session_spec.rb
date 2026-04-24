# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::CancelOnboardingSession, type: :service do
  let(:hotel) { create(:hotel) }
  let(:session) { create(:onboarding_session, hotel: hotel, status: "scheduled") }
  let(:reason) { "Test cancellation reason" }

  subject { described_class.new(session, reason) }

  describe "#call" do
    it "cancels the session and appends the reason to notes" do
      result = subject.call
      expect(result.success?).to be true
      expect(session.reload.status).to eq("cancelled")
      expect(session.notes).to include("CANCELLED: #{reason}")
    end

    context "when session is not scheduled" do
      let(:session) { create(:onboarding_session, hotel: hotel, status: "completed") }

      it "returns a failure result" do
        result = subject.call
        expect(result.success?).to be false
        expect(result.error).to eq("Only scheduled sessions can be cancelled.")
      end
    end

    context "when reason is blank" do
      let(:reason) { "" }

      it "returns a failure result" do
        result = subject.call
        expect(result.success?).to be false
        expect(result.error).to eq("Please provide a reason before cancelling the session.")
      end
    end
  end
end
