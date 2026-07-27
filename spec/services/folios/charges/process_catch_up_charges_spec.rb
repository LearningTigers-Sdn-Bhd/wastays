# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Charges::ProcessCatchUpCharges, type: :service do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, role: "superadmin") }
  let(:past_date) { 1.day.ago.to_date }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", check_in: past_date, check_out: past_date + 1.day) }
  let(:folio) { create(:booking_folio, booking: booking) }

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    create(:booking_room, booking: booking, subtotal: 200.0)
    booking.update(tax_lines: [ { "name" => "SST", "amount" => "12.00" } ])
    folio
    # Ensure folio exists and is linked
    booking.reload
  end

  context "when night audit for the stay date is completed" do
    before do
      create(:night_audit, hotel: hotel, business_date: past_date, status: "completed")
      create(:hotel_business_date, hotel: hotel, business_date: past_date, status: "closed")
    end

    it "posts missing nightly charges with backdated check-in descriptions by default" do
      expect {
        described_class.call(booking: booking, user: user)
      }.to change { folio.folio_transactions.count }.by(2) # Room charge + SST

      room_charge = folio.folio_transactions.find_by(category: "accommodation")
      expect(room_charge.amount).to eq(200.0)
      expect(room_charge.description).to eq("Backdated Check-in (Room Charge) - #{past_date.strftime('%d %b %Y')}")
      expect(room_charge.metadata["stay_date"]).to eq(past_date.iso8601)
      expect(room_charge.metadata["posting_source"]).to eq("catch_up")
      expect(room_charge.catch_up_key).to eq("catch_up:#{booking.id}:#{past_date.iso8601}:accommodation:#{booking.booking_rooms.first.id}")
      expect(room_charge.metadata["catch_up_key"]).to eq(room_charge.catch_up_key)
      expect(room_charge.posting_date).to eq(past_date)

      tax_charge = folio.folio_transactions.find_by(category: "tax")
      expect(tax_charge.amount).to eq(12.0)
      expect(tax_charge.description).to eq("Backdated Check-in Tax: SST - #{past_date.strftime('%d %b %Y')}")
      expect(tax_charge.catch_up_key).to eq("catch_up:#{booking.id}:#{past_date.iso8601}:tax:sst:0")
      expect(tax_charge.metadata["catch_up_key"]).to eq(tax_charge.catch_up_key)
    end

    it "does not duplicate catch-up charges when retried" do
      described_class.call(booking: booking, user: user)

      expect {
        described_class.call(booking: booking, user: user)
      }.not_to change { folio.folio_transactions.charge.count }

      expect(folio.folio_transactions.charge.where(category: "accommodation").count).to eq(1)
      expect(folio.folio_transactions.charge.where(category: "tax").count).to eq(1)
    end

    it "does not duplicate catch-up charges posted on another folio for the same booking" do
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
      room = booking.booking_rooms.first
      catch_up_key = Folios::Charges::ChargePostingKeys.catch_up_charge_key(booking: booking, date: past_date, charge_kind: "accommodation", identity: room.id)
      create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", category: "accommodation", amount: 200.0, catch_up_key: catch_up_key, metadata: { catch_up_key: catch_up_key })

      expect {
        described_class.call(booking: booking, user: user)
      }.to change { folio.folio_transactions.charge.count }.by(1)

      expect(folio.folio_transactions.charge.where(category: "tax").count).to eq(1)
      expect(company_folio.folio_transactions.charge.where(category: "accommodation").count).to eq(1)
    end

    it "routes ROOM and scheduled tax catch-up lines by their transaction codes" do
      hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
      booking.update!(tax_posting_snapshot: {
        past_date.iso8601 => [ { "name" => "SST", "amount" => "12.00", "type" => "sst", "transaction_code_id" => sst_code.id } ]
      })
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: sst_code, target_folio: folio)

      described_class.call(booking: booking, user: user)

      expect(company_folio.folio_transactions.charge.find_by(category: "accommodation").transaction_code).to eq(room_code)
      expect(folio.folio_transactions.charge.find_by(category: "tax").transaction_code).to eq(sst_code)
    end

    it "routes attached tax catch-up lines with the parent ROOM rule" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
      booking.update!(tax_posting_snapshot: {
        past_date.iso8601 => [
          {
            "name" => "SST",
            "amount" => "12.00",
            "type" => "sst",
            "transaction_code_id" => sst_code.id,
            "source_transaction_code_id" => room_code.id
          }
        ]
      })
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

      described_class.call(booking: booking, user: user)

      expect(company_folio.folio_transactions.charge.pluck(:category)).to contain_exactly("accommodation", "tax")
    end

    it "does not duplicate a legacy metadata-only catch-up transaction" do
      room = booking.booking_rooms.first
      catch_up_key = "catch_up:#{booking.id}:#{past_date.iso8601}:accommodation:#{room.id}"
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: "charge",
        category: "accommodation",
        amount: 200.0,
        catch_up_key: nil,
        metadata: { catch_up_key: catch_up_key })

      expect {
        described_class.call(booking: booking, user: user)
      }.to change { folio.folio_transactions.charge.count }.by(1)

      expect(folio.folio_transactions.charge.where(category: "accommodation").count).to eq(1)
      expect(folio.folio_transactions.charge.where(category: "tax").count).to eq(1)
    end

    it "enforces catch-up uniqueness at the database level" do
      catch_up_key = "catch_up:#{booking.id}:#{past_date.iso8601}:accommodation:#{booking.booking_rooms.first.id}"
      create(:folio_transaction, booking_folio: folio, catch_up_key: catch_up_key)

      expect {
        create(:folio_transaction, booking_folio: folio, catch_up_key: catch_up_key)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "posts charges with reinstate description when is_reinstate is true" do
      booking_r = create(:booking, hotel: hotel, status: "checked_in", check_in: past_date, check_out: past_date + 1.day)
      booking_r.update(tax_lines: [ { "name" => "SST", "amount" => "12.00" } ])
      create(:booking_room, booking: booking_r, subtotal: 200.0)
      folio_r = create(:booking_folio, booking: booking_r)

      described_class.call(booking: booking_r, user: user, is_reinstate: true)
      folio_r.reload

      room_charge = folio_r.folio_transactions.charge.where(category: "accommodation").where("metadata->>'is_reinstate' = ?", "true").last
      expect(room_charge).to be_present
      expect(room_charge.description).to include("Reinstate Charge")

      tax_charge = folio_r.folio_transactions.charge.where(category: "tax").where("metadata->>'is_reinstate' = ?", "true").last
      expect(tax_charge).to be_present
      expect(tax_charge.description).to include("Reinstate Tax")
    end

    it "reverses existing no-show charges with specific descriptions" do
      booking_p = create(:booking, hotel: hotel, status: "checked_in", check_in: past_date, check_out: past_date + 1.day)
      folio_p = create(:booking_folio, booking: booking_p)

      charge = create(:folio_transaction,
        booking_folio: folio_p,
        transaction_type: "charge",
        category: "no_show_charge",
        amount: 50.0,
        metadata: { posting_source: "no_show" }
      )
      payment = create(:folio_transaction,
        booking_folio: folio_p,
        transaction_type: "payment",
          category: "booking_payment",
        amount: 25.0,
        metadata: { posting_source: "no_show" }
      )

      # Test default reversal
      described_class.call(booking: booking_p, user: user)
      folio_p.reload
      reversal = folio_p.folio_transactions.adjustment.where("metadata->>'reversed_transaction_id' = ?", charge.id.to_s).last
      expect(reversal).to be_present
      expect(reversal.description).to include("Auto-reversal of no-show charge")
      payment_reversal = folio_p.folio_transactions.adjustment.where("metadata->>'reversed_transaction_id' = ?", payment.id.to_s).last
      expect(payment_reversal).to be_nil

      # Test reinstate reversal
      charge2 = create(:folio_transaction,
        booking_folio: folio_p,
        transaction_type: "charge",
        category: "no_show_charge",
        amount: 50.0,
        metadata: { posting_source: "no_show" }
      )
      described_class.call(booking: booking_p, user: user, is_reinstate: true)
      folio_p.reload
      reversal2 = folio_p.folio_transactions.adjustment.where("metadata->>'reversed_transaction_id' = ?", charge2.id.to_s)
                                                  .where("metadata->>'is_reinstate' = ?", "true").last
      expect(reversal2).to be_present
      expect(reversal2.description).to eq("Void Charge: Reinstated Reservation")
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
