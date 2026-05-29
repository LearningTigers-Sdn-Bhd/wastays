# frozen_string_literal: true

module HotelKnowledges
  class PdfParsingError < StandardError; end

  class PdfParsingService
    def initialize(file_path)
      @file_path = file_path
    end

    def call
      text = extract_text
      cleaned = clean(text)
      raise PdfParsingError, "No extractable text found in PDF" if cleaned.blank?
      cleaned
    end

    private

    attr_reader :file_path

    def extract_text
      PDF::Reader.new(file_path).pages.map(&:text).join("\n")
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
      raise PdfParsingError, "Failed to parse PDF: #{e.message}"
    end

    def clean(text)
      text
        .gsub(/\f+/, "\n")
        .gsub(/^\s*\d+\s*$/, "")
        .gsub(/[^\S\n]+/, " ")
        .squeeze("\n")
        .strip
    end
  end
end
