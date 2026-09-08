# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # House Rules: how guests behave in the property. Visitors, parties, quiet
    # hours, damage, keys, and general safety.
    class PolicyHouseRulesController < HotelPortal::GuestContent::PolicyDocumentsController
      self.policy_key = "house_rules"
      self.document_title = "House Rules"
      self.notice = "House rules saved."

      private

      def policy_path
        hotel_policy_house_rules_path(@hotel)
      end
    end
  end
end
