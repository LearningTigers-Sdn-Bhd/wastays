# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ProcessCatchUpCharges, type: :service do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:past_date) { 1.day.ago.to_date }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_in: past_date, check_out: past_date + 1.day) }
  let(:folio) { create(:booking_folio, booking: booking) }

  before do
    create(:booking_room, booking: booking, subtotal: 200.0)
    booking.update(tax_lines: [ { "name" => "SST", "amount" => "12.00" } ])
    # Ensure folio exists and is linked
    booking.reload
  end

  context "when night audit for the stay date is completed" do
    before do
      create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")
    end

    it "posts missing nightly charges" do
      expect {
        described_class.call(booking: booking, user: user)
      }.to change { folio.folio_transactions.count }.by(2) # Room charge + SST

      room_charge = folio.folio_transactions.find_by(category: "accommodation")
      expect(room_charge.amount).to eq(200.0)
      expect(room_charge.metadata["stay_date"]).to eq(past_date.iso8601)
      expect(room_charge.metadata["posting_source"]).to eq("catch_up")

      tax_charge = folio.folio_transactions.find_by(category: "tax")
      expect(tax_charge.amount).to eq(12.0)
    end

    it "reverses existing no-show penalties" do
      penalty = create(:folio_transaction,
        booking_folio: folio,
        transaction_type: "charge",
        category: "no_show_penalty",
        amount: 50.0,
        metadata: { posting_source: "no_show" }
      )

      expect {
        described_class.call(booking: booking, user: user)
      }.to change { folio.folio_transactions.adjustment.count }.by(1)

      reversal = folio.folio_transactions.adjustment.last
      expect(reversal.amount).to eq(-50.0)
      expect(reversal.metadata["reversed_transaction_id"]).to eq(penalty.id)
    end
  end

  context "when night audit for the stay date is NOT completed" do
    it "does not post charges" do
      expect {
        described_class.call(booking: booking, user: user)
      }.not_to change { folio.folio_transactions.count }
    end
  end
end
