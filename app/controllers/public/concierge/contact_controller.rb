module Public
  module Concierge
    class ContactController < BaseController
      include ConciergeContactDetails

      def show
        load_contact_details
      end
    end
  end
end
