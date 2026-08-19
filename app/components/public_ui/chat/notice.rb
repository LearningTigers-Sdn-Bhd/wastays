# frozen_string_literal: true

module PublicUI
  module Chat
    # A quiet strip above the composer telling the guest who is on the other end
    # -- the front desk when the bot is off, a named person once staff take over.
    class Notice < PublicUI::BaseComponent
      TONES = %i[muted accent].freeze

      def initialize(text: nil, tone: :muted, class: nil, **attributes)
        @text = text
        @tone = TONES.include?(tone) ? tone : :muted
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.p(content.presence || @text, **attributes.merge(
          class: tw_merge("public-chat__notice", @class),
          data: data.merge(tone: @tone)
        ))
      end
    end
  end
end
