# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class KnowledgeGeneralInfosController < HotelPortal::GuestContent::DocumentsController
      self.category = "general_info"
      self.plural_route = "knowledge_general_infos"
      self.singular_route = "knowledge_general_info"
      self.label = "Information"
      self.noun = "General info document"
    end
  end
end
