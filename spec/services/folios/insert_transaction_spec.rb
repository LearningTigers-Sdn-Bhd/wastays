# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::InsertTransaction do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking) }
  let(:user) { create(:user) }

  describe "#call" do
    context "on an open business date" do
      it "creates a transaction successfully" do
        result = described_class.new(
          booking_folio: folio,
          amount: 100.0,
          transaction_type: :charge,
          category: "fb",
          user: user,
          description: "Breakfast"
        ).call

        expect(result.success?).to be true
        expect(result.transaction.amount).to eq(100.0)
        expect(folio.outstanding_balance).to eq(100.0)
      end

      it "allows system transactions without a user" do
        result = described_class.new(
          booking_folio: folio,
          amount: 100.0,
          transaction_type: :payment,
          category: "gateway_payment",
          user: nil,
          description: "Gateway payment"
        ).call

        expect(result.success?).to be true
        expect(result.transaction.user).to be_nil
      end
    end

    context "on a closed business date" do
      let(:closed_date) { 1.day.ago.to_date }
      before do
        create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed")
      end

      it "fails without override" do
        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "other",
          user: user,
          posting_date: closed_date
        ).call

        expect(result.success?).to be false
        expect(result.error).to include("already closed")
      end

      it "succeeds with override" do
        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "other",
          user: user,
          posting_date: closed_date,
          options: { override_night_audit: true }
        ).call

        expect(result.success?).to be true
        expect(folio.outstanding_balance).to eq(50.0)
      end
    end
  end
end
