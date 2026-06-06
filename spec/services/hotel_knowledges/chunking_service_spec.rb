# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::ChunkingService do
  describe "#call" do
    subject(:chunks) { described_class.new(text, source_type: source_type).call }

    let(:source_type) { "text" }

    context "with blank text" do
      let(:text) { "" }

      it { is_expected.to be_empty }
    end

    context "with short text" do
      let(:text) { "This is a short piece of content." }

      it "returns a single chunk" do
        expect(chunks.size).to eq(1)
        expect(chunks.first[:content]).to eq(text)
        expect(chunks.first[:chunk_index]).to eq(0)
      end
    end

    context "with long text that exceeds max tokens" do
      let(:text) { ("word " * 600).strip }

      it "splits into multiple chunks" do
        expect(chunks.size).to be > 1
      end

      it "assigns sequential chunk indices" do
        indices = chunks.map { |c| c[:chunk_index] }
        expect(indices).to eq((0...chunks.size).to_a)
      end
    end

    context "with PDF source type and double-newline sections" do
      let(:source_type) { "pdf" }
      let(:text) { "Section one content here.\n\nSection two content here.\n\nSection three content here." }

      it "splits on double newlines" do
        expect(chunks.size).to eq(3)
        expect(chunks[0][:content]).to eq("Section one content here.")
        expect(chunks[1][:content]).to eq("Section two content here.")
        expect(chunks[2][:content]).to eq("Section three content here.")
      end
    end

    context "with PDF source type and very short sections" do
      let(:source_type) { "pdf" }
      let(:text) { "Hi.\n\nLong content here that has enough tokens to be meaningful.\n\nBye." }

      it "discards very short sections" do
        expect(chunks.size).to eq(1)
        expect(chunks.first[:content]).to eq("Long content here that has enough tokens to be meaningful.")
      end
    end

    context "with PDF source type and no clear sections" do
      let(:source_type) { "pdf" }
      let(:text) { ("token " * 600).strip }

      it "falls back to fixed token split" do
        expect(chunks.size).to be > 1
      end
    end
  end
end
