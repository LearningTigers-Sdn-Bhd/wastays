# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingEngine::VerifyCorporateDomain do
  let(:partner) { create(:partner, domain: "company.com") }
  let(:quote) { double("quote", partner: partner) }

  describe "#call" do
    context "when partner is blank" do
      let(:quote) { double("quote", partner: nil) }

      it "returns valid: true" do
        result = described_class.new(quote: quote, email: "test@example.com").call
        expect(result[:valid]).to be true
      end
    end

    context "when partner domain is blank" do
      let(:partner) { create(:partner, domain: nil) }

      it "returns valid: true" do
        result = described_class.new(quote: quote, email: "test@example.com").call
        expect(result[:valid]).to be true
      end
    end

    context "when email domain matches partner domain" do
      it "returns valid: true with success message" do
        result = described_class.new(quote: quote, email: "employee@company.com").call
        expect(result[:valid]).to be true
        expect(result[:message]).to include("Work email verified")
      end

      it "handles case sensitivity and whitespace" do
        result = described_class.new(quote: quote, email: " EMPLOYEE@COMPANY.COM ").call
        expect(result[:valid]).to be true
      end
    end

    context "when email domain does not match partner domain" do
      it "returns valid: false with error message" do
        result = described_class.new(quote: quote, email: "test@gmail.com").call
        expect(result[:valid]).to be false
        expect(result[:message]).to include("only valid for @company.com")
      end
    end
  end
end
