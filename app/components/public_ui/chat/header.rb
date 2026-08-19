# frozen_string_literal: true

module PublicUI
  module Chat
    # Who the guest is talking to, held above the thread.
    #
    # A long conversation scrolls the page heading away, and the names above the
    # bubbles only appear at the start of a run -- so on a phone, halfway down a
    # thread, nothing on screen says which hotel this is. This does, and stays
    # put while the thread moves under it.
    class Header < PublicUI::BaseComponent
      def initialize(title:, subtitle: nil, class: nil, **attributes)
        @title = title
        @subtitle = subtitle
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        tag.div(**@attributes.merge(class: tw_merge("public-chat__header", @class))) do
          safe_join([ title, subtitle ].compact)
        end
      end

      private

      def title = tag.p(@title, class: "public-chat__header-title")

      def subtitle
        return if @subtitle.blank?

        tag.p(@subtitle, class: "public-chat__header-subtitle")
      end
    end
  end
end
