# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class KnowledgeFaqsController < HotelPortal::GuestContent::DocumentsController
      self.category = "faq"
      self.plural_route = "knowledge_faqs"
      self.singular_route = "knowledge_faq"
      self.label = "FAQ"
      self.noun = "FAQ document"

      private

      # An FAQ keeps its questions and answers in metadata. The content column
      # is the flattened text that the AI Concierge reads.
      def save_document
        assign_metadata_and_content
        @document.save
      end

      def document_params
        params.require(:hotel_knowledge_document).permit(
          :title, :source_type, :language,
          :effective_date, :file, :tags
        )
      end

      def assign_metadata_and_content
        raw_metadata = params.dig(:hotel_knowledge_document, :metadata)
        return unless raw_metadata

        @document.metadata = raw_metadata.to_unsafe_h
        qa_pairs = @document.metadata&.dig("qa_pairs")
        return if qa_pairs.blank?

        # Handle hash-like array parameters from indexed form fields
        if qa_pairs.is_a?(Hash)
          qa_pairs = qa_pairs.values
          @document.metadata["qa_pairs"] = qa_pairs
        end
        return unless qa_pairs.is_a?(Array)

        qa_pairs.reject! { |pair| pair["question"].blank? && pair["answer"].blank? }
        return if qa_pairs.empty?

        @document.content = qa_pairs.map { |pair|
          "Q: #{pair['question']}\nA: #{pair['answer']}"
        }.join("\n\n")
      end
    end
  end
end
