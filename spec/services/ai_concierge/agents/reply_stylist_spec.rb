# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Agents::ReplyStylist do
  let(:hotel) { create(:hotel, :with_ai_concierge, ai_concierge_tone: "cheerful") }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:context) { instance_double(RubyLLM::Context, chat: chat) }
  let(:config) { double("ruby_llm_config") }

  before do
    allow(config).to receive(:openai_api_key=)
    allow(RubyLLM).to receive(:context).and_yield(config).and_return(context)
    allow(chat).to receive(:with_temperature).and_return(chat)
  end

  def style(template: "Your total is RM 480.00.", guest_message: "berapa harga bilik?", thread_language: "en")
    described_class.new(hotel: hotel, template: template, guest_message: guest_message, thread_language: thread_language).call
  end

  describe "whether it runs at all" do
    def styles?(tone: "basic", thread_language: "en", guest_message: "1")
      hotel.ai_concierge_tone = tone
      described_class.styles?(hotel: hotel, thread_language: thread_language, guest_message: guest_message)
    end

    it "stays out of the way when the guest answered with nothing but a number" do
      expect(styles?(guest_message: "1")).to be(false)
      expect(styles?(guest_message: "21/08")).to be(false)
    end

    it "reads anything the guest actually wrote, even for a hotel with no tone set" do
      expect(styles?(guest_message: "ada bilik kosong?")).to be(true)
    end

    it "keeps running once the thread is in another language" do
      expect(styles?(thread_language: "ms", guest_message: "2")).to be(true)
    end

    it "always runs for a hotel that picked a tone" do
      expect(styles?(tone: "cheerful", guest_message: "1")).to be(true)
    end
  end

  it "returns the rewritten reply, the language it was written in and the one it was read in" do
    allow(chat).to receive(:ask).and_return(double(content: '{"guest_language":"ms","language":"ms","text":"Jumlah anda RM 480.00."}'))

    result = style

    expect(context).to have_received(:chat).with(model: hotel.ai_concierge_model_name, provider: hotel.ai_concierge_provider)
    expect(result.text).to eq("Jumlah anda RM 480.00.")
    expect(result.language).to eq("ms")
    expect(result.guest_language).to eq("ms")
  end

  # Rewriting a finished sentence has no upside left to sample for, and the
  # providers all default to 1.0.
  it "asks for no randomness at all" do
    allow(chat).to receive(:ask).and_return(double(content: '{"guest_language":"ms","language":"ms","text":"Jumlah anda RM 480.00."}'))

    style

    expect(chat).to have_received(:with_temperature).with(0)
  end

  # An absence, however the model spells it. Recording one of these as a
  # language is what used to move a thread the guest never moved.
  it "reads every way a model says the message had no language in it" do
    %w[null NULL und].each do |absence|
      allow(chat).to receive(:ask).and_return(double(content: %({"guest_language":"#{absence}","language":"en","text":"Sure."})))

      expect(style(guest_message: "1").guest_language).to be_nil
    end

    allow(chat).to receive(:ask).and_return(double(content: '{"guest_language":null,"language":"en","text":"Sure."}'))

    expect(style(guest_message: "1").guest_language).to be_nil
  end

  # An instruction with the answer already in it, not a rule to work out. A
  # model handed a resolved target writes the right language far more often
  # than one asked to decide which target applies.
  it "tells the model the tone, the guest's words and orders a language outright" do
    allow(chat).to receive(:ask).and_return(double(content: '{"guest_language":null,"language":"ms","text":"Jumlah anda RM 480.00."}'))

    style(guest_message: "1", thread_language: "ms")

    expect(chat).to have_received(:ask) do |prompt|
      expect(prompt).to include(described_class::TONES.fetch("cheerful"))
      expect(prompt).to include("Your total is RM 480.00.")
      expect(prompt).to include("Write the reply in ms.")
      expect(prompt).not_to match(/too short to tell/)
    end
  end

  # Fencing JSON in markdown is the single most common thing a model does to a
  # JSON instruction, and failing the turn over three backticks would send the
  # guest a template for no reason.
  it "reads JSON the model fenced in markdown" do
    allow(chat).to receive(:ask).and_return(double(content: "```json\n{\"guest_language\":\"en\",\"language\":\"en\",\"text\":\"Sure thing!\"}\n```"))

    expect(style.text).to eq("Sure thing!")
  end

  it "keeps the thread's language when the model names none" do
    allow(chat).to receive(:ask).and_return(double(content: '{"text":"Baik!"}'))

    expect(style(thread_language: "ms").language).to eq("ms")
  end

  it "raises when the model answers with prose instead of JSON" do
    allow(chat).to receive(:ask).and_return(double(content: "Sure, here is a nicer version."))

    expect { style }.to raise_error(described_class::ReplyStylistError, /no JSON/)
  end

  it "raises when the rewritten reply is empty" do
    allow(chat).to receive(:ask).and_return(double(content: '{"guest_language":"en","language":"en","text":"   "}'))

    expect { style }.to raise_error(described_class::ReplyStylistError, /empty/)
  end

  it "raises a wrapped error when RubyLLM fails" do
    allow(chat).to receive(:ask).and_raise(RubyLLM::Error.new("bad request"))

    expect { style }.to raise_error(described_class::ReplyStylistError, /API error/)
  end
end
