# frozen_string_literal: true

module PublicUI
  module Chat
    # The box the guest types into.
    class Composer < PublicUI::BaseComponent
      def initialize(url:, param: :message, label: "Your message",
                     placeholder: "Type your message...", submit_label: "Send →",
                     rows: 3, class: nil, **attributes)
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
