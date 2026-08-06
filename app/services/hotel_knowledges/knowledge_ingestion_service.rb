# frozen_string_literal: true

module HotelKnowledges
  class IngestionError < StandardError; end

  class KnowledgeIngestionService
    def initialize(document)
      @document = document
    end

    def call
      chunks_data = build_chunks
      return mark_indexed if chunks_data.empty?

      texts = chunks_data.map { |c| c[:content] }
      embeddings = EmbeddingService.new(hotel: @document.hotel).call(texts)

      chunk_records = chunks_data.each_with_index.map do |chunk, idx|
        {
          hotel_knowledge_document_id: @document.id,
          content: chunk[:content],
          chunk_index: chunk[:chunk_index],
          embedding: embeddings[idx],
          token_count: chunk[:content].split.length,
          metadata: {},
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      ActiveRecord::Base.transaction do
        @document.chunks.destroy_all
        HotelKnowledgeChunk.insert_all(chunk_records)
        @document.update!(embedding_status: "indexed", metadata: @document.metadata.except("last_error"))
      end

      @document.chunks.reload
    rescue StandardError => e
      @document.update!(
        embedding_status: "failed",
        metadata: @document.metadata.merge("last_error" => e.message)
      )
      raise IngestionError, e.message
    end

    private

    attr_reader :document

    def build_chunks
      text = if @document.source_type == "pdf"
               parse_pdf_text
      else
               @document.content.to_s
      end

      ChunkingService.new(text, source_type: @document.source_type).call
    end

    def parse_pdf_text
      file = @document.file
      raise IngestionError, "No file attached" unless file.attached?

      Dir.mktmpdir("pdf_parsing") do |dir|
        path = File.join(dir, file.filename.to_s)
        file.download { |chunk| File.open(path, "ab") { |f| f.write(chunk) } }
        PdfParsingService.new(path).call
      end
    end

    def mark_indexed
      @document.update!(embedding_status: "indexed", metadata: @document.metadata.except("last_error"))
    end
  end
end
