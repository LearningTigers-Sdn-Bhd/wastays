# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class KnowledgeGeneralInfosController < HotelPortal::GuestContent::DocumentsController
      self.category = "general_info"
      self.plural_route = "knowledge_general_infos"
      self.singular_route = "knowledge_general_info"
      self.label = "Information"
      self.noun = "General info document"

      def index; end

      def additional_information
        @documents = category_scope.order(created_at: :desc)
      end

      private

      def kb_index_path
        hotel_knowledge_additional_information_path(@hotel)
      end
    end
  end
end
