module Public
  module Concierge
    module Stays
      # The property's contacts, reached from the stay page. The same contacts as
      # the public page, with the stay card as the way back.
      class ContactsController < BaseController
        include ConciergeContactDetails

        def show
          @presenter = stay_presenter
          load_contact_details
        end
      end
    end
  end
end
