# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::VoucherWallet do
  subject(:wallet) { described_class.new(session: session, booking: booking) }

  let(:session) { {} }
  let(:booking) { instance_double(Booking, id: 42) }
  let(:offer) { VendorDirectory.vendors.find { |vendor| vendor.offers.any? }.offers.first }

  describe "#claim!" do
    it "records the claim and reports it as claimed" do
      expect(wallet.claimed?(offer)).to be(false)

      entry = wallet.claim!(offer)

      expect(entry.offer_id).to eq(offer.id)
      expect(entry.vendor_id).to eq(offer.vendor_id)
      expect(wallet.claimed?(offer)).to be(true)
    end

    # Claiming twice must not mint a second code: the guest holds one voucher,
    # and the code is what the vendor scans.
    it "returns the existing voucher rather than issuing another" do
      first = wallet.claim!(offer)
      second = wallet.claim!(offer)

      expect(second.code).to eq(first.code)
      expect(wallet.size).to eq(1)
    end

    it "issues a code shaped like the one the vendor will scan" do
      expect(wallet.claim!(offer).code).to match(/\AWS-[A-Z0-9]{1,4}-[A-Z0-9]{6}\z/)
    end
  end

  describe "scoping to a booking" do
    # The key carries the booking id, so a second stay in the same browser
    # starts with an empty wallet rather than inheriting the last guest's.
    it "does not show one booking's vouchers to another" do
      wallet.claim!(offer)
      other = described_class.new(session: session, booking: instance_double(Booking, id: 99))

      expect(other.claimed?(offer)).to be(false)
      expect(other.entries).to be_empty
    end
  end

  describe "#entries" do
    it "is empty before anything is claimed" do
      expect(wallet.entries).to be_empty
      expect(wallet.any?).to be(false)
    end

    it "lists the newest claim first" do
      vendors = VendorDirectory.vendors.select { |vendor| vendor.offers.any? }
      skip "fixture needs two vendors with offers" if vendors.size < 2

      # Parenthesised on purpose: `travel_to x { ... }` binds the block to the
      # argument expression, not to travel_to, and the body never runs.
      travel_to(Time.zone.parse("2026-09-14 10:00")) { wallet.claim!(vendors.first.offers.first) }
      travel_to(Time.zone.parse("2026-09-14 11:00")) { wallet.claim!(vendors.second.offers.first) }

      expect(wallet.entries.first.vendor_id).to eq(vendors.second.id)
      expect(wallet.entries.size).to eq(2)
    end

    # A live session can outlast an edit to the fixture. An entry pointing at a
    # vendor that no longer exists is dropped rather than raising on the wallet.
    it "drops an entry whose vendor has disappeared from the directory" do
      wallet.claim!(offer)
      session[described_class::SESSION_KEY]["42:gone-vendor:gone-offer"] =
        { "code" => "WS-GONE-ABCDEF", "claimed_at" => Time.current.iso8601 }

      expect { wallet.entries }.not_to raise_error
      expect(wallet.entries.map(&:vendor_id)).not_to include("gone-vendor")
    end
  end
end
