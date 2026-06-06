# frozen_string_literal: true

module HotelPortal
  class KnowledgeFaqsController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :authorize_hotel
    before_action :set_document, only: %i[show edit update destroy reindex]

    helper_method :kb_index_path, :kb_show_path, :kb_edit_path, :kb_new_path, :kb_reindex_path

    def index
      @documents = @hotel.knowledge_documents.where(category: "faq").order(created_at: :desc)
    end

    def show
      @chunks = @document.chunks.order(:chunk_index)
      render "hotel_portal/knowledge_base/show"
    end

    def new
      @document = @hotel.knowledge_documents.build(category: "faq")
      render "hotel_portal/knowledge_base/new"
    end

    def create
      @document = @hotel.knowledge_documents.build(document_params.merge(category: "faq"))
      assign_metadata_and_content

      if @document.save
        redirect_to kb_index_path, notice: "FAQ document created successfully."
      else
        render "hotel_portal/knowledge_base/new", status: :unprocessable_content
      end
    end

    def edit
      render "hotel_portal/knowledge_base/edit"
    end

    def update
      @document.attributes = document_params
      assign_metadata_and_content

      if @document.save
        redirect_to kb_index_path, notice: "FAQ document updated successfully."
      else
        render "hotel_portal/knowledge_base/edit", status: :unprocessable_content
      end
    end

    def destroy
      @document.destroy!
      redirect_to kb_index_path, notice: "FAQ document deleted successfully."
    end

    def reindex
      HotelKnowledges::GenerateEmbeddingsJob.perform_later(@document.id)
      redirect_to kb_show_path(@document), notice: "Embedding generation started."
    end

    private

    def kb_index_path
      hotel_knowledge_faqs_path(@hotel)
    end

    def kb_show_path(doc)
      hotel_knowledge_faq_path(@hotel, doc)
    end

    def kb_edit_path(doc)
      edit_hotel_knowledge_faq_path(@hotel, doc)
    end

    def kb_new_path
      new_hotel_knowledge_faq_path(@hotel)
    end

    def kb_reindex_path(doc)
      reindex_hotel_knowledge_faq_path(@hotel, doc)
    end

    def set_hotel
      @hotel = current_hotel
    end

    def authorize_hotel
      authorize @hotel, :update?, policy_class: HotelPolicy
    end

    def set_document
      @document = @hotel.knowledge_documents.where(category: "faq").find(params[:id])
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
      return unless qa_pairs.present?

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
