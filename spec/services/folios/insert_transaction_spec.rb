# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::InsertTransaction do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking) }
  let(:user) { create(:user, role: "superadmin") }

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
          description: "Late charge",
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
          description: "Late charge",
          posting_date: closed_date,
          options: {
            override_night_audit: true,
            correction_reason: "late_charge",
            correction_note: "Approved closed-date posting."
          }
        ).call

        expect(result.success?).to be true
        expect(folio.outstanding_balance).to eq(50.0)
      end
    end

    context "while night audit is running" do
      before do
        create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_running")
      end

      it "blocks normal staff postings" do
        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "other",
          user: user,
          description: "Late charge"
        ).call

        expect(result.success?).to be(false)
        expect(result.error).to include("currently in night audit")
      end

      it "allows night audit postings" do
        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "accommodation",
          user: user,
          description: "Nightly room charge",
          options: { posting_source: "night_audit" }
        ).call

        expect(result.success?).to be(true)
      end
    end

    context "while night audit is blocked" do
      let(:night_audit) { create(:night_audit, hotel: hotel, business_date: Date.current, status: "blocked") }

      before do
        create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_blocked")
      end

      it "blocks normal staff postings" do
        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "other",
          user: user,
          description: "Late charge"
        ).call

        expect(result.success?).to be(false)
        expect(result.error).to include("blocked by night audit")
      end

      it "allows blocker-resolution postings with context and reason" do
        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :payment,
          category: "gateway_payment",
          user: user,
          description: "Sync blocked payment",
          options: {
            posting_source: "audit_blocker_resolution",
            correction_reason: "Resolve captured payment blocker",
            blocker_resolution: { night_audit_id: night_audit.id, blocker_type: "captured_payment_not_synced" }
          }
        ).call

        expect(result.success?).to be(true)
      end
    end

    context "on a closed folio" do
      it "fails without override" do
        stale_folio = BookingFolio.find(folio.id)
        folio.update!(status: "closed")

        result = described_class.new(
          booking_folio: stale_folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "other",
          user: user,
          description: "Late charge"
        ).call

        expect(result.success?).to be(false)
        expect(result.error).to include("Folio is closed")
      end

      it "succeeds with override" do
        folio.update!(status: "closed")

        result = described_class.new(
          booking_folio: folio,
          amount: 50.0,
          transaction_type: :charge,
          category: "other",
          user: user,
          description: "Late charge",
          options: {
            override_closed_folio: true,
            correction_reason: "late_charge",
            correction_note: "Approved closed-folio posting."
          }
        ).call

        expect(result.success?).to be(true)
        expect(folio.outstanding_balance).to eq(50.0)
      end
    end
  end
end
