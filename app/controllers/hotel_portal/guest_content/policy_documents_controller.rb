# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The fixed cards on the Policies page are the same single-document editor
    # over different policy keys. A subclass declares its key, its title, and
    # where it returns to. Everything else is inherited.
    class PolicyDocumentsController < HotelPortal::GuestContent::BaseController
      class_attribute :policy_key, :document_title, :notice, instance_writer: false

      helper_method :policy_document

      def show
        policy_document
      end

      def update
        @service = ::GuestContent::SavePolicyDocument.new(@hotel, policy_key, document_title, document_content)
        @document = @service.document

        if @service.call
          redirect_to policy_path, notice: notice
        else
          render :show, status: :unprocessable_content
        end
      end

      private

      def policy_document
        @document ||= @hotel.knowledge_documents.where(category: "policy").with_policy_key(policy_key).first ||
          @hotel.knowledge_documents.build(category: "policy", source_type: "text", title: document_title)
      end

      def document_content
        params.require(:hotel_knowledge_document).permit(:content)[:content]
      end

      # Subclasses point back at their own sub-tab.
      def policy_path
        raise NotImplementedError
      end
    end
  end
end
