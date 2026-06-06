# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::EmbeddingService do
  subject(:service) { described_class.new(hotel: hotel) }

  let(:hotel) { create(:hotel, ai_provider_name: "openai", ai_provider_key: "sk-test-key") }

  describe "#call" do
    context "with an array of texts" do
      let(:texts) { [ "Hello world", "Second text" ] }
      let(:mock_vectors) { [ [ 0.1 ] * 1536, [ 0.2 ] * 1536 ] }
      let(:mock_response) { instance_double(RubyLLM::Embedding, vectors: mock_vectors) }

      before do
        allow(RubyLLM::Embedding).to receive(:embed).and_return(mock_response)
      end

      it "returns vectors for each text" do
        result = service.call(texts)
        expect(result.size).to eq(2)
        expect(result.first).to be_an(Array)
        expect(result.first.size).to eq(1536)
      end

      it "calls RubyLLM::Embedding.embed with correct model and dimensions" do
        service.call(texts)
        expect(RubyLLM::Embedding).to have_received(:embed) do |batch, **kwargs|
          expect(batch).to eq(texts)
          expect(kwargs[:model]).to eq("text-embedding-3-small")
          expect(kwargs[:dimensions]).to eq(1536)
        end
      end
    end

    context "with a single text" do
      let(:texts) { "Just one string" }
      let(:mock_vectors) { [ [ 0.5 ] * 1536 ] }
      let(:mock_response) { instance_double(RubyLLM::Embedding, vectors: mock_vectors) }

      before do
        allow(RubyLLM::Embedding).to receive(:embed).and_return(mock_response)
      end

      it "wraps single string in array and returns array of arrays" do
        result = service.call(texts)
        expect(result).to be_an(Array)
        expect(result.first).to be_an(Array)
      end
    end

    context "with empty array" do
      it "returns empty array" do
        expect(service.call([])).to eq([])
      end
    end

    context "with hotel using non-OpenAI provider" do
      let(:hotel) { create(:hotel, ai_provider_name: "claude", ai_provider_key: "sk-claude-key") }

      before do
        allow(AppConfig).to receive(:get).with("openai_api_key").and_return("sk-app-config-key")
        allow(RubyLLM::Embedding).to receive(:embed).and_return(
          instance_double(RubyLLM::Embedding, vectors: [ [ 0.1 ] * 1536 ])
        )
      end

      it "falls back to AppConfig key" do
        service.call([ "test" ])
        expect(RubyLLM::Embedding).to have_received(:embed)
      end
    end

    context "with no API key available" do
      let(:hotel) { create(:hotel, ai_provider_name: "claude", ai_provider_key: nil) }

      before do
        allow(AppConfig).to receive(:get).with("openai_api_key").and_return(nil)
      end

      it "raises EmbeddingError" do
        expect { service.call([ "test" ]) }.to raise_error(HotelKnowledges::EmbeddingError, /No OpenAI API key/)
      end
    end

    context "when RubyLLM raises an error" do
      before do
        allow(RubyLLM::Embedding).to receive(:embed).and_raise(RubyLLM::Error.new("API error"))
      end

      it "wraps the error in EmbeddingError" do
        expect { service.call([ "test" ]) }.to raise_error(HotelKnowledges::EmbeddingError, /API error/)
      end
    end

    context "with batch processing" do
      let(:texts) { ("a".."z").to_a }
      let(:mock_vectors) { [ [ 0.1 ] * 1536 ] * 20 }
      let(:mock_response) { instance_double(RubyLLM::Embedding, vectors: mock_vectors) }

      before do
        allow(RubyLLM::Embedding).to receive(:embed).and_return(mock_response)
      end

      it "processes in batches of 20" do
        service.call(texts)
        expect(RubyLLM::Embedding).to have_received(:embed).at_least(:twice)
      end
    end
  end
end
