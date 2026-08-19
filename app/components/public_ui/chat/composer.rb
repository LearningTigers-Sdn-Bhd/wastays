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
    end
  end
end
