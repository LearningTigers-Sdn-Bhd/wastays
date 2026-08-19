# frozen_string_literal: true

module PublicUI
  module Chat
    # The chat card: thread, notice, composer.
    #
    # Owns the Stimulus controller the thread and the composer are targets of, so
    # a page composes the three pieces without knowing they talk to each other.
    class Panel < PublicUI::BaseComponent
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
