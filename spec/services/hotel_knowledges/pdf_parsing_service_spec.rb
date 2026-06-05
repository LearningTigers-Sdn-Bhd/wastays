# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::PdfParsingService do
  describe "#call" do
    subject(:call) { described_class.new(file_path).call }

    context "with a valid PDF" do
      let(:file_path) do
        path = Rails.root.join("tmp", "test_sample.pdf")
        Prawn::Document.generate(path) do |pdf|
          pdf.text "Hello World"
          pdf.text "Page 2 content", start_new_page: true
        end
        path
      end

      after { File.delete(file_path) if File.exist?(file_path) }

      it "extracts text from the PDF" do
        result = call
        expect(result).to include("Hello World")
        expect(result).to include("Page 2 content")
      end

      it "returns cleaned text without page numbers" do
        expect(call).not_to match(/^\d+$/)
      end
    end

    context "with a blank PDF" do
      let(:file_path) do
        path = Rails.root.join("tmp", "test_blank.pdf")
        Prawn::Document.generate(path) { |pdf| pdf.text "" }
        path
      end

      after { File.delete(file_path) if File.exist?(file_path) }

      it "raises PdfParsingError" do
        expect { call }.to raise_error(HotelKnowledges::PdfParsingError, /No extractable text/)
      end
    end

    context "with a non-existent file" do
      let(:file_path) { "/nonexistent/file.pdf" }

      it "raises an error" do
        expect { call }.to raise_error(StandardError)
      end
    end
  end
end
