# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledgeDiagnostic do
  it "is valid with required attributes" do
    diagnostic = build(:hotel_knowledge_diagnostic)

    expect(diagnostic).to be_valid
  end

  it "validates diagnostic status" do
    diagnostic = build(:hotel_knowledge_diagnostic, diagnostic_status: "queued")

    expect(diagnostic).not_to be_valid
    expect(diagnostic.errors[:diagnostic_status]).to be_present
  end

  it "validates suggested category when present" do
    diagnostic = build(:hotel_knowledge_diagnostic, suggested_category: "spa")

    expect(diagnostic).not_to be_valid
    expect(diagnostic.errors[:suggested_category]).to be_present
  end

  it "scopes diagnostics by filters" do
    open = create(:hotel_knowledge_diagnostic, diagnostic_status: "open", answer_mode: "unavailable", suggested_category: "faq")
    create(:hotel_knowledge_diagnostic, hotel: open.hotel, diagnostic_status: "resolved", answer_mode: "deterministic", suggested_category: "policy")

    result = open.hotel.knowledge_diagnostics
      .for_status("open")
      .for_answer_mode("unavailable")
      .for_suggested_category("faq")

    expect(result).to contain_exactly(open)
  end
end
