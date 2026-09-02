# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::Localizer do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:chat) { double("translation chat") }
  let(:client) { double("RubyLlmClient", chat: chat) }

  before do
    allow(chat).to receive(:with_temperature).with(0).and_return(chat)
    allow(chat).to receive(:ask)
    allow(AiConcierge::Providers::RubyLlmClient).to receive(:new).with(hotel: hotel).and_return(client)
    allow(AiConcierge::Providers::UsageLog).to receive(:call)
  end

  it "returns English knowledge copy without calling a model" do
    result = described_class.new(hotel: hotel, reply: "Check-in starts at 3:00 PM.", language: "en").call

    expect(result).to eq("Check-in starts at 3:00 PM.")
    expect(chat).not_to have_received(:ask)
  end

  it "translates Malay while preserving bullets, facts, and times" do
    response = double(content: '{"text":"Butiran yang tersedia ialah:\n- Daftar masuk bermula pada 3:00 PM.\n- Daftar keluar adalah pada 11:00 AM."}')
    allow(chat).to receive(:ask).and_return(response)
    original = "Here are the available details:\n- Check-in starts at 3:00 PM.\n- Check-out is at 11:00 AM."

    result = described_class.new(hotel: hotel, reply: original, language: "ms").call

    expect(result).to include("3:00 PM", "11:00 AM")
    expect(result.lines.count { |line| line.start_with?("- ") }).to eq(2)
    expect(AiConcierge::Providers::UsageLog).to have_received(:call).with(response, hotel: hotel, stage: :knowledge_translation)
  end

  it "translates Chinese without changing room names or formatting" do
    create(:room_type, hotel: hotel, name: "Garden Suite")
    allow(chat).to receive(:ask).and_return(
      double(content: '{"text":"现有详情：\n- Garden Suite 可容纳 2 位成人。"}')
    )
    original = "Here are the available details:\n- Garden Suite accommodates 2 adults."

    result = described_class.new(hotel: hotel, reply: original, language: "zh").call

    expect(result).to eq("现有详情：\n- Garden Suite 可容纳 2 位成人。")
  end

  it "falls back to English when a translation changes a protected fact" do
    allow(chat).to receive(:ask).and_return(double(content: '{"text":"Daftar masuk bermula pada 4:00 PM."}'))
    original = "Check-in starts at 3:00 PM."

    expect(described_class.new(hotel: hotel, reply: original, language: "ms").call).to eq(original)
  end

  it "keeps a translated sales-action line" do
    allow(chat).to receive(:ask).and_return(
      double(content: '{"text":"Daftar masuk bermula pada 3:00 PM.\n\nAdakah anda mahu saya membantu mencari bilik?"}')
    )
    original = "Check-in starts at 3:00 PM.\n\nWould you like me to help you find a room?"

    result = described_class.new(hotel: hotel, reply: original, language: "ms").call

    expect(result).to end_with("Adakah anda mahu saya membantu mencari bilik?")
    expect(result).to include("3:00 PM")
  end

  it "falls back to English when a translation removes the sales-action line" do
    allow(chat).to receive(:ask).and_return(double(content: '{"text":"Daftar masuk bermula pada 3:00 PM."}'))
    original = "Check-in starts at 3:00 PM.\n\nWould you like me to help you find a room?"

    expect(described_class.new(hotel: hotel, reply: original, language: "ms").call).to eq(original)
  end

  it "removes duplicate punctuation from a valid translation" do
    allow(chat).to receive(:ask).and_return(
      double(content: '{"text":"Pasar malam terletak berhampiran hotel.."}')
    )
    original = "The night market is near the hotel."

    result = described_class.new(hotel: hotel, reply: original, language: "ms").call

    expect(result).to eq("Pasar malam terletak berhampiran hotel.")
  end

  it "removes duplicate Chinese terminal punctuation" do
    allow(chat).to receive(:ask).and_return(double(content: '{"text":"夜市就在酒店附近。。"}'))
    original = "The night market is near the hotel."

    result = described_class.new(hotel: hotel, reply: original, language: "zh").call

    expect(result).to eq("夜市就在酒店附近。")
  end
end
