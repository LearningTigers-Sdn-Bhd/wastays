# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestContent::SavePolicyDocument do
  let(:hotel) { create(:hotel) }

  def documents
    hotel.knowledge_documents.where(category: "policy").reload
  end

  describe "the first save" do
    it "creates one policy document under the key of its card" do
      expect(described_class.call(hotel, "house_rules", "House Rules", "Quiet hours run from 10 PM.")).to be(true)

      document = documents.sole
      expect(document.title).to eq("House Rules")
      expect(document.category).to eq("policy")
      expect(document.source_type).to eq("text")
      expect(document.content).to eq("Quiet hours run from 10 PM.")
      expect(document.metadata["policy_key"]).to eq("house_rules")
    end

    it "writes nothing when the hotel saved an empty card" do
      expect(described_class.call(hotel, "house_rules", "House Rules", "   ")).to be(true)

      expect(documents).to be_empty
    end
  end

  describe "a later save" do
    it "rewrites the same document rather than adding a second one" do
      described_class.call(hotel, "payment_and_deposits", "Payment and Deposits", "Pay on arrival.")
      described_class.call(hotel, "payment_and_deposits", "Payment and Deposits", "Pay on departure.")

      expect(documents.count).to eq(1)
      expect(documents.sole.content).to eq("Pay on departure.")
    end

    # An empty policy still answers a guest, and answers wrong. Removing the row
    # is what stops the AI Concierge from quoting a blank rule.
    it "removes the document when the hotel clears the text" do
      described_class.call(hotel, "payment_and_deposits", "Payment and Deposits", "Pay on arrival.")

      expect(described_class.call(hotel, "payment_and_deposits", "Payment and Deposits", "")).to be(true)
      expect(documents).to be_empty
    end
  end

  it "keeps one card apart from another" do
    described_class.call(hotel, "house_rules", "House Rules", "No parties.")
    described_class.call(hotel, "room_terms", "Room Terms", "A child is under 12.")

    expect(documents.pluck(:title)).to contain_exactly("House Rules", "Room Terms")
  end

  it "leaves a free policy alone" do
    free = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Parking")

    described_class.call(hotel, "house_rules", "House Rules", "No parties.")

    expect(free.reload.metadata["policy_key"]).to be_nil
    expect(documents.count).to eq(2)
  end
end
