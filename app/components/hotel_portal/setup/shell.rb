# frozen_string_literal: true

module HotelPortal
  module Setup
    # The onboarding page frame: fixed stepper header, scrolling body, resting
    # footer.
    #
    # The footer is a flex sibling of the scroll container rather than a sticky
    # element inside it, so it never overlaps content, errors, or the last field
    # of a long form. Because the header carries the only rule on the page (the
    # line-tab underline), sections inside the body separate with spacing alone.
    class Shell < PanelsUI::BaseComponent
      renders_one :body
      renders_one :footer

      def initialize(presenter:)
        @presenter = presenter
      end

      attr_reader :presenter
    end
  end
end
