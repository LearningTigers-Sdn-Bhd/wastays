# frozen_string_literal: true

module HotelKnowledges
  class ChunkingService
    MAX_TOKENS = 512
    OVERLAP_TOKENS = 64

    def initialize(text, source_type: "text")
      @text = text.to_s.strip
      @source_type = source_type
    end

    def call
      return [] if @text.blank?

      if @source_type == "pdf"
        chunks = section_based_split
        chunks = chunks.flat_map { |s| token_count(s) > MAX_TOKENS ? fixed_token_split_for(s) : [ s ] }
        chunks = fixed_token_split if chunks.empty?
      else
        chunks = text_split
      end

      chunks.each_with_index.map do |content, idx|
        { content: content.strip, chunk_index: idx }
      end
    end

    private

    def section_based_split
      sections = @text.split(/\n{2,}/).map(&:strip).reject(&:blank?)
      return [] if sections.empty?

      sections.reject { |s| token_count(s) < 3 }
    end

    def fixed_token_split
      fixed_token_split_for(@text)
    end

    def text_split
      if token_count(@text) <= MAX_TOKENS
        [ @text ]
      else
        paragraphs = @text.split(/\n{2,}/).map(&:strip).reject(&:blank?)
        chunks = []
        buffer = []

        paragraphs.each do |para|
          if token_count(para) > MAX_TOKENS
            chunks << buffer.join("\n\n") if buffer.any?
            buffer = []
            chunks.concat(fixed_token_split_for(para))
          elsif token_count((buffer + [ para ]).join("\n\n")) > MAX_TOKENS && buffer.any?
            chunks << buffer.join("\n\n")
            buffer = [ para ]
          else
            buffer << para
          end
        end

        chunks << buffer.join("\n\n") if buffer.any?
        chunks
      end
    end

    def fixed_token_split_for(text)
      words = text.split
      chunks = []
      idx = 0

      while idx < words.length
        chunk_words = []
        count = 0

        while idx < words.length && count + 1 <= MAX_TOKENS
          chunk_words << words[idx]
          count += 1
          idx += 1
        end

        chunks << chunk_words.join(" ")
        idx -= OVERLAP_TOKENS if idx < words.length
      end

      chunks
    end

    def token_count(text)
      text.split.length
    end
  end
end
