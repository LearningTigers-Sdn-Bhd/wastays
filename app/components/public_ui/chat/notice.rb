# frozen_string_literal: true

module PublicUI
  module Chat
    # A quiet strip above the composer telling the guest who is on the other end
    # -- the front desk when the bot is off, a named person once staff take over.
    #
    # It always renders something, even with nothing to say: the empty div is
    # what a live replacement is aimed at when the answer changes mid-thread,
    # and an anchor that only exists while there is a message is no anchor.
    class Notice < PublicUI::BaseComponent
      DEFAULT_ID = "concierge-chat-notice"
      TONES = %i[muted accent].freeze

      def initialize(text: nil, tone: :muted, id: DEFAULT_ID, class: nil, **attributes)
        @text = text
        @tone = TONES.include?(tone) ? tone : :muted
        @id = id
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        body = content.presence || @text
        # `display: contents` on the empty anchor: it has to stay in the DOM for
        # a live replacement to be aimed at, but a nothing that still opens a gap
        # between the thread and the box is a nothing you can see.
        return tag.div(id: @id, class: "public-chat__notice-anchor") if body.blank?

        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.p(body, **attributes.merge(
          id: @id,
          class: tw_merge("public-chat__notice", @class),
          data: data.merge(tone: @tone)
        ))
      end
    end
  end
end
