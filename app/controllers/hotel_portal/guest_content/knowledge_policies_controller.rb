# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Other Policies: everything the four fixed cards do not cover. A hotel can
    # name these anything, so they stay a free list.
    #
    # The scope drops the documents a fixed card owns. Those are edited on their
    # own sub-tab, and would otherwise show twice.
    class KnowledgePoliciesController < HotelPortal::GuestContent::DocumentsController
      self.category = "policy"
      self.plural_route = "knowledge_policies"
      self.singular_route = "knowledge_policy"
      self.label = "Policy"
      self.noun = "Policy document"

      private

      def category_scope
        super.without_policy_key
      end
    end
  end
end
