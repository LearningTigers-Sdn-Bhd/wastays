# frozen_string_literal: true

module PublicUI
  module Chat
    class QuickReplies < PublicUI::BaseComponent
      def initialize(suggestions:, message_url:)
        @suggestions = suggestions
        @message_url = message_url
      end

      private

      attr_reader :suggestions, :message_url
    end
  end
end
