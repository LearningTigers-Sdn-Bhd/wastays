# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class KnowledgePoliciesController < HotelPortal::GuestContent::DocumentsController
      self.category = "policy"
      self.plural_route = "knowledge_policies"
      self.singular_route = "knowledge_policy"
      self.label = "Policy"
      self.noun = "Policy document"
    end
  end
end
