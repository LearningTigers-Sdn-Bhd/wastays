# frozen_string_literal: true

module PublicUI
  module Chat
    # The line under the hotel's name saying who is answering -- the assistant,
    # the front desk, or a named person once staff take over.
    #
    # Its own component rather than markup inside the bar because it is what a
    # live update is aimed at: the moment staff take the thread, this line has
    # to change under a guest who is already reading the page, and nothing else
    # in the bar may move.
    class Status < PublicUI::BaseComponent
      DEFAULT_ID = "concierge-chat-status"
      TONES = %i[muted accent].freeze

      def initialize(text: nil, tone: :muted, id: DEFAULT_ID, class: nil, **attributes)
        @text = text
        @tone = TONES.include?(tone) ? tone : :muted
        @id = id
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.p(content.presence || @text, **attributes.merge(
          id: @id,
          class: tw_merge("public-chat__status", @class),
          data: data.merge(tone: @tone)
        ))
      end
    end
  end
end
