# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCodes::Resolver do
  let(:hotel) { create(:hotel) }
  let(:resolver) { described_class.for(hotel) }

  describe "#for_key" do
    it "finds a code by its system key" do
      expect(resolver.for_key("room_revenue")).to eq(hotel.transaction_codes.find_by!(system_key: "room_revenue"))
    end

    it "accepts a symbol" do
      expect(resolver.for_key(:room_revenue)).to eq(hotel.transaction_codes.find_by!(system_key: "room_revenue"))
    end

    it "returns nil for a blank or unknown key" do
      expect(resolver.for_key(nil)).to be_nil
      expect(resolver.for_key("")).to be_nil
      expect(resolver.for_key("not_a_key")).to be_nil
    end

    it "does not leak codes from another hotel" do
      other_hotel = create(:hotel)

      expect(resolver.for_key("room_revenue").hotel).to eq(hotel)
      expect(resolver.for_key("room_revenue")).not_to eq(other_hotel.transaction_codes.find_by!(system_key: "room_revenue"))
    end

    it "memoizes a hit rather than querying again" do
      expect(resolver.for_key("room_revenue")).to be(resolver.for_key("room_revenue"))
    end

    it "picks up a code created after an earlier miss" do
      hotel.transaction_codes.find_by!(system_key: "sst_tax").destroy!
      expect(resolver.for_key("sst_tax")).to be_nil

      recreated = hotel.transaction_codes.create!(system_key: "sst_tax", code: "TAX_SST", name: "SST", kind: "tax", category: "tax")

      expect(resolver.for_key("sst_tax")).to eq(recreated)
    end
  end

  describe "#for_key!" do
    it "returns the code when present" do
      expect(resolver.for_key!("room_revenue")).to eq(hotel.transaction_codes.find_by!(system_key: "room_revenue"))
    end

    it "raises when the code is missing" do
      expect { resolver.for_key!("not_a_key") }.to raise_error(ActiveRecord::RecordNotFound, /not_a_key/)
    end
  end

  describe "#room_revenue" do
    it "resolves the room revenue code" do
      expect(resolver.room_revenue).to eq(hotel.transaction_codes.find_by!(system_key: "room_revenue"))
    end
  end

  describe "#for_id" do
    it "finds a code belonging to the hotel" do
      code = hotel.transaction_codes.find_by!(system_key: "room_revenue")

      expect(resolver.for_id(code.id)).to eq(code)
    end

    it "returns nil for a blank id" do
      expect(resolver.for_id(nil)).to be_nil
      expect(resolver.for_id("")).to be_nil
    end

    it "returns nil for a code belonging to another hotel" do
      foreign_code = create(:hotel).transaction_codes.find_by!(system_key: "room_revenue")

      expect(resolver.for_id(foreign_code.id)).to be_nil
    end
  end

  describe "#for_tax_type" do
    it "maps tax line vocabulary onto system keys" do
      expect(resolver.for_tax_type("sst")).to eq(hotel.transaction_codes.find_by!(system_key: "sst_tax"))
      expect(resolver.for_tax_type("tourism_tax")).to eq(hotel.transaction_codes.find_by!(system_key: "tourism_tax"))
    end

    it "returns nil for an unmapped or blank type" do
      expect(resolver.for_tax_type("custom")).to be_nil
      expect(resolver.for_tax_type(nil)).to be_nil
    end
  end

  describe "#for_tax_line" do
    it "prefers the transaction code the line names explicitly" do
      named = hotel.transaction_codes.find_by!(system_key: "tourism_tax")

      expect(resolver.for_tax_line({ "type" => "sst", "transaction_code_id" => named.id })).to eq(named)
    end

    it "falls back to the code for the line's type" do
      expect(resolver.for_tax_line({ "type" => "sst" })).to eq(hotel.transaction_codes.find_by!(system_key: "sst_tax"))
    end

    it "reads symbol keys as well as string keys" do
      expect(resolver.for_tax_line({ type: "sst" })).to eq(hotel.transaction_codes.find_by!(system_key: "sst_tax"))

      named = hotel.transaction_codes.find_by!(system_key: "tourism_tax")
      expect(resolver.for_tax_line({ transaction_code_id: named.id })).to eq(named)
    end

    it "accepts anything that converts to a hash" do
      expect(resolver.for_tax_line(ActionController::Parameters.new(type: "sst").permit!)).to eq(hotel.transaction_codes.find_by!(system_key: "sst_tax"))
    end

    it "returns nil for a line with neither an explicit code nor a known type" do
      expect(resolver.for_tax_line({ "type" => "custom" })).to be_nil
      expect(resolver.for_tax_line({})).to be_nil
    end
  end

  describe "#source_for_tax_line" do
    it "resolves the code the tax was levied on" do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")

      expect(resolver.source_for_tax_line({ "source_transaction_code_id" => room_code.id })).to eq(room_code)
      expect(resolver.source_for_tax_line({ source_transaction_code_id: room_code.id })).to eq(room_code)
    end

    it "returns nil when the line records no source" do
      expect(resolver.source_for_tax_line({ "type" => "sst" })).to be_nil
    end
  end
end
