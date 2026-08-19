# frozen_string_literal: true

module PublicUI
  module Chat
    # The chat card: thread, notice, composer.
    #
    # Owns the Stimulus controller the thread and the composer are targets of, so
    # a page composes the three pieces without knowing they talk to each other.
    class Panel < PublicUI::BaseComponent
      # The id of the region a send replaces. It sits on the wrapper rather than
      # on the panel itself because the stream subscription has to travel with
      # it -- a page that has just gained its first thread needs the
      # subscription and the thread in the same replacement.
      REGION_ID = "concierge-chat-region"

      renders_one :header, ->(**args) { Header.new(**args) }
      renders_one :log, ->(**args) { Log.new(**args) }
      renders_one :notice, ->(**args) { Notice.new(**args) }
      renders_one :composer, ->(**args) { Composer.new(**args) }

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
