# frozen_string_literal: true

module PublicUI
  module Chat
    # The box the guest types into.
    #
    # One row on the bottom edge of the chat: a field that grows with what is
    # being written, and a button beside it. The label is read out but not
    # drawn -- with the box fixed under the thread there is nothing else it
    # could be for, and a line of chrome above it costs a line of conversation.
    class Composer < PublicUI::BaseComponent
      def initialize(url:, param: :message, label: "Your message",
                     placeholder: "Type your message...", submit_label: "Send",
                     rows: 1, class: nil, **attributes)
        @url = url
        @param = param
        @label = label
        @placeholder = placeholder
        @submit_label = submit_label
        @rows = rows
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      private

      attr_reader :url, :param, :label, :placeholder, :submit_label, :rows

      def form_class = tw_merge("public-chat__composer", @class)

      # Enter sends and Shift+Enter breaks the line, which is what every other
      # chat does; the box has to say so, because a field that submits on Enter
      # when nothing told you it would is a message sent half-written.
      def input_actions
        [
          "input->concierge-chat#growInput",
          "keydown->concierge-chat#onInputKeydown"
        ].join(" ")
      end

      # The box is emptied here rather than by replacing it: replacing the
      # textarea takes the focus and the phone keyboard with it, and a guest
      # sending three quick messages would have to tap back in each time.
      def form_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        attributes.merge(
          class: form_class,
          data: data.merge(action: [ data[:action], "turbo:submit-end->concierge-chat#onSubmitEnd" ].compact_blank.join(" "))
        )
      end
    end
  end
end
