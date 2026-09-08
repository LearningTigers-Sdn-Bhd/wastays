# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # House Rules: how guests behave in the property. Visitors, parties, quiet
    # hours, damage, keys, and general safety.
    #
    # The emergency contacts sit beside the rules, read-only. Guests already see
    # them on the concierge contact page, so showing them here stops a hotel
    # from typing a second copy into the rules.
    class PolicyHouseRulesController < HotelPortal::GuestContent::PolicyDocumentsController
      self.policy_key = "house_rules"
      self.document_title = "House Rules"
      self.notice = "House rules saved."

      before_action :load_guest_contact

      private

      def load_guest_contact
        @guest_contact = @hotel.guest_contact || @hotel.build_guest_contact
      end

      def policy_path
        hotel_policy_house_rules_path(@hotel)
      end
    end
  end
end
