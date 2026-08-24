# frozen_string_literal: true

module PublicUI
  module Chat
    # Who the guest is talking to, and the way back out.
    #
    # Fixed at the top of the chat while the thread scrolls under it. The thread
    # itself cannot say who it belongs to: the names above the bubbles only
    # appear at the start of a run, so halfway down a long conversation nothing
    # on screen would name the hotel.
    #
    # The `menu` slot is where actions on the whole conversation live -- the
    # thread is a stream of one guest's words, so anything that acts on all of
    # it belongs here rather than beside a message.
    class Bar < PublicUI::BaseComponent
      AVATARS = { bot: "bot", staff: "headset" }.freeze

      renders_one :menu

      def initialize(title:, status: {}, back_path: nil, back_label: "Back", avatar: :bot,
                     class: nil, **attributes)
        @title = title
        @status = status || {}
        @back_path = back_path
        @back_label = back_label
        @avatar = AVATARS.key?(avatar) ? avatar : :bot
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      private

      attr_reader :title, :back_path, :back_label

      def bar_class = tw_merge("public-chat__bar", @class)

      def avatar_icon = AVATARS.fetch(@avatar)

      def status_component = Status.new(**@status)
    end
  end
end
