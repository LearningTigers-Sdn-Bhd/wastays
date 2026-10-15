# frozen_string_literal: true

module GuestUI
  # One entry a guest opens to read: an amenity, a policy, a question.
  #
  # The title is the summary, so a long list stays one line per entry until the
  # guest opens the one they need. It is a native <details>, so it opens with a
  # tap, Enter, or Space and a screen reader announces it as expanded or
  # collapsed, with no script.
  #
  # Entries sit one under the other, divided by a hairline, as card rows are.
  class Disclosure < GuestUI::BaseComponent
    def initialize(title:, open: false, class: nil, **attributes)
      @title = title
      @open = open
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def render? = content.present?

    def call
      tag.details(**@attributes, class: tw_merge("guest-disclosure", @class), open: @open) do
        safe_join([ summary, tag.div(content, class: "guest-disclosure__body") ])
      end
    end

    private

    def summary
      tag.summary do
        safe_join([
          tag.span(@title, class: "guest-disclosure__title"),
          helpers.app_icon("chevron-down", class: "guest-disclosure__chevron", aria: { hidden: "true" })
        ])
      end
    end
  end
end
