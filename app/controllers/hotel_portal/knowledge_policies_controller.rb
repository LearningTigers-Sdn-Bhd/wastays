# frozen_string_literal: true

module HotelPortal
  class KnowledgePoliciesController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :authorize_hotel
    before_action :set_document, only: %i[show edit update destroy]

    helper_method :kb_index_path, :kb_show_path, :kb_edit_path, :kb_new_path

    def index
      @documents = @hotel.knowledge_documents.where(category: "policy").order(created_at: :desc)
    end

    def show
      @chunks = @document.chunks.order(:chunk_index)
      render "hotel_portal/knowledge_base/show"
    end

    def new
      @document = @hotel.knowledge_documents.build(category: "policy")
      render "hotel_portal/knowledge_base/new"
    end

    def create
      @document = @hotel.knowledge_documents.build(document_params.merge(category: "policy"))

      if @document.save
        redirect_to kb_index_path, notice: "Policy document created successfully."
      else
        render "hotel_portal/knowledge_base/new", status: :unprocessable_content
      end
    end

    def edit
      render "hotel_portal/knowledge_base/edit"
    end

    def update
      if @document.update(document_params)
        redirect_to kb_index_path, notice: "Policy document updated successfully."
      else
        render "hotel_portal/knowledge_base/edit", status: :unprocessable_content
      end
    end

    def destroy
      @document.destroy!
      redirect_to kb_index_path, notice: "Policy document deleted successfully."
    end

    private

    def kb_index_path
      hotel_knowledge_policies_path(@hotel)
    end

    def kb_show_path(doc)
      hotel_knowledge_policy_path(@hotel, doc)
    end

    def kb_edit_path(doc)
      edit_hotel_knowledge_policy_path(@hotel, doc)
    end

    def kb_new_path
      new_hotel_knowledge_policy_path(@hotel)
    end

    def set_hotel
      @hotel = current_hotel
    end

    def authorize_hotel
      authorize @hotel, :update?, policy_class: HotelPolicy
    end

    def set_document
      @document = @hotel.knowledge_documents.where(category: "policy").find(params[:id])
    end

    def document_params
      params.require(:hotel_knowledge_document).permit(
        :title, :source_type, :language,
        :effective_date, :content, :file, :metadata, :tags
      )
    end
  end
end
