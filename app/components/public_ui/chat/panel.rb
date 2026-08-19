# frozen_string_literal: true

module PublicUI
  module Chat
    # The chat itself: bar, thread, composer, stacked to fill whatever height it
    # is given.
    #
    # Three rows, and only the middle one scrolls -- the bar and the box stay
    # where the guest last saw them, which is what makes this read as a
    # messenger rather than as a page with a conversation on it.
    #
    # Owns the Stimulus controller the thread and the composer are targets of,
    # so a page composes the pieces without knowing they talk to each other.
    class Panel < PublicUI::BaseComponent
      # The id of the region the whole chat lives in. It sits on the wrapper
      # rather than on the panel itself because the stream subscription has to
      # travel with it.
      REGION_ID = "concierge-chat-region"

      renders_one :bar, PublicUI::Chat::Bar
      renders_one :log, PublicUI::Chat::Log
      # Sits with the composer rather than at the top of the page: what it has
      # to say is always about the message the guest just tried to send, and
      # that is where they are looking.
      renders_one :alert
      renders_one :composer, PublicUI::Chat::Composer

      def initialize(class: nil, **attributes)
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def root_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        attributes.merge(
          class: tw_merge("public-chat", @class),
          data: data.reverse_merge(controller: "concierge-chat")
        )
      end
    end
  end
end
