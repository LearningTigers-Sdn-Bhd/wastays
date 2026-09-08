# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Policies, FAQs, and Hotel Info are the same document CRUD on three
    # categories. Only the category, the route names, and the notice wording
    # change, so subclasses declare those and inherit the rest.
    class DocumentsController < HotelPortal::GuestContent::BaseController
      include SheetActionCompletion

      class_attribute :category, :plural_route, :singular_route, :noun, :label, instance_writer: false

      before_action :set_document, only: %i[show edit update destroy reindex]

      helper_method :kb_index_path, :kb_create_path, :kb_show_path, :kb_edit_path, :kb_new_path,
                    :kb_reindex_path, :kb_label

      def index
        @documents = category_scope.order(created_at: :desc)
      end

      def show
        @chunks = @document.chunks.order(:chunk_index)
        render "hotel_portal/guest_content/documents/show", layout: false
      end

      def new
        @document = @hotel.knowledge_documents.build(category: category)
        render "hotel_portal/guest_content/documents/new", layout: false
      end

      def create
        @document = @hotel.knowledge_documents.build(document_params.merge(category: category))

        if save_document
          finish_sheet("#{noun} created successfully.")
        else
          render "hotel_portal/guest_content/documents/new", formats: :html, layout: false, status: :unprocessable_content
        end
      end

      def edit
        render "hotel_portal/guest_content/documents/edit", layout: false
      end

      def update
        @document.attributes = document_params

        if save_document
          finish_sheet("#{noun} updated successfully.")
        else
          render "hotel_portal/guest_content/documents/edit", formats: :html, layout: false, status: :unprocessable_content
        end
      end

      def destroy
        @document.destroy!
        redirect_to kb_index_path, notice: "#{noun} deleted successfully."
      end

      def reindex
        unless @hotel.ai_concierge_enabled?
          redirect_to kb_index_path, alert: "AI Concierge must be enabled before generating embeddings."
          return
        end

        @document.enqueue_embedding_generation!
        redirect_to kb_index_path, notice: "Embedding generation started."
      end

      private

      # The sheet closes itself and then reloads the list behind it.
      def finish_sheet(notice)
        complete_sheet_action(
          destination: kb_index_path,
          notice: notice,
          frame: turbo_frame_request_id.presence || "settings_action_sheet"
        )
      end

      def kb_label
        label
      end

      # FAQs build their content from question and answer pairs before the save.
      def save_document
        @document.save
      end

      def category_scope
        @hotel.knowledge_documents.where(category: category)
      end

      def kb_index_path
        public_send("hotel_#{plural_route}_path", @hotel)
      end

      # Where the form posts. It is the collection route, which is not always
      # the page the operator came from: Hotel Info lists its documents on a
      # sub-tab of its own, and that path answers GET only.
      def kb_create_path
        public_send("hotel_#{plural_route}_path", @hotel)
      end

      def kb_show_path(document)
        public_send("hotel_#{singular_route}_path", @hotel, document)
      end

      def kb_edit_path(document)
        public_send("edit_hotel_#{singular_route}_path", @hotel, document)
      end

      def kb_new_path
        public_send("new_hotel_#{singular_route}_path", @hotel)
      end

      def kb_reindex_path(document)
        public_send("reindex_hotel_#{singular_route}_path", @hotel, document)
      end

      def set_document
        @document = category_scope.find(params[:id])
      end

      def document_params
        params.require(:hotel_knowledge_document).permit(
          :title, :source_type, :language,
          :effective_date, :content, :file, :metadata, :tags
        )
      end
    end
  end
end
