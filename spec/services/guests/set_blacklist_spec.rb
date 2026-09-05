# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::SetBlacklist do
  let!(:hotel) { create(:hotel) }
  let!(:other_hotel) { create(:hotel) }
  let!(:actor) { create(:user) }

  describe "#call" do
    context "when it blacklists" do
      it "records the property id, the reason and the actor" do
        guest = create(:guest, created_by_hotel: hotel)

        result = described_class.new(
          guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "Damaged the room"
        ).call

        expect(result.success?).to be true
        expect(result.changed_count).to eq(1)

        guest.reload
        expect(guest.blacklisted).to be true
        expect(guest.blacklisted_at?(hotel)).to be true
        expect(guest.metadata["blacklisted_hotel_ids"]).to eq([ hotel.id ])

        detail = guest.blacklist_detail(hotel)
        expect(detail["reason"]).to eq("Damaged the room")
        expect(detail["blacklisted_by_id"]).to eq(actor.id)
        expect(detail["blacklisted_by_name"]).to eq(actor.name)
        expect(detail["blacklisted_at"]).to be_present
      end

      it "leaves the guest clear at another property" do
        guest = create(:guest, created_by_hotel: hotel)

        described_class.new(guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "No show").call

        expect(guest.reload.blacklisted_at?(other_hotel)).to be false
      end

      it "does not add the same property twice" do
        guest = create(:guest, created_by_hotel: hotel)

        described_class.new(guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "First").call
        result = described_class.new(guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "Second").call

        expect(result.changed_count).to eq(0)
        expect(guest.reload.metadata["blacklisted_hotel_ids"]).to eq([ hotel.id ])
      end

      it "fails without a reason" do
        guest = create(:guest, created_by_hotel: hotel)

        result = described_class.new(guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "  ").call

        expect(result.success?).to be false
        expect(result.message).to include("provide a reason")
        expect(guest.reload.blacklisted).to be false
      end
    end

    context "when it clears the blacklist" do
      it "drops the property id and its detail" do
        guest = create(:guest, created_by_hotel: hotel)
        described_class.new(guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "Damage").call

        result = described_class.new(guests: guest, hotel: hotel, blacklisted: false, actor: actor).call

        expect(result.success?).to be true
        guest.reload
        expect(guest.blacklisted).to be false
        expect(guest.blacklisted_at?(hotel)).to be false
        expect(guest.metadata["blacklisted_hotel_ids"]).to eq([])
        expect(guest.blacklist_detail(hotel)).to be_nil
      end

      it "keeps the column true while another property still holds a blacklist" do
        guest = create(:guest, created_by_hotel: hotel)
        described_class.new(guests: guest, hotel: hotel, blacklisted: true, actor: actor, reason: "A").call
        described_class.new(guests: guest, hotel: other_hotel, blacklisted: true, actor: actor, reason: "B").call

        described_class.new(guests: guest, hotel: hotel, blacklisted: false, actor: actor).call

        guest.reload
        expect(guest.blacklisted).to be true
        expect(guest.blacklisted_at?(hotel)).to be false
        expect(guest.blacklisted_at?(other_hotel)).to be true
      end

      it "clears a legacy record that carries the column but no property ids" do
        guest = create(:guest, created_by_hotel: hotel, blacklisted: true, metadata: {})
        expect(guest.blacklisted_at?(hotel)).to be true

        result = described_class.new(guests: guest, hotel: hotel, blacklisted: false, actor: actor).call

        expect(result.success?).to be true
        guest.reload
        expect(guest.blacklisted).to be false
        expect(guest.blacklisted_at?(hotel)).to be false
      end
    end

    context "with more than one guest record" do
      it "counts only the records that change" do
        already = create(:guest, created_by_hotel: hotel)
        described_class.new(guests: already, hotel: hotel, blacklisted: true, actor: actor, reason: "Old").call
        fresh = create(:guest, created_by_hotel: hotel)

        result = described_class.new(
          guests: [ already, fresh ], hotel: hotel, blacklisted: true, actor: actor, reason: "Group"
        ).call

        expect(result.changed_count).to eq(1)
        expect(fresh.reload.blacklisted_at?(hotel)).to be true
        expect(already.reload.blacklist_detail(hotel)["reason"]).to eq("Old")
      end
    end

    it "fails when nothing is selected" do
      result = described_class.new(guests: [], hotel: hotel, blacklisted: true, actor: actor, reason: "x").call

      expect(result.success?).to be false
      expect(result.message).to include("No guest records selected")
    end
  end
end
