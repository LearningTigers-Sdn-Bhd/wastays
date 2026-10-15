# frozen_string_literal: true

module GuestUI
  module Chat
    class QuickReplies < GuestUI::BaseComponent
      def initialize(suggestions:, message_url:)
        @suggestions = suggestions
        @message_url = message_url
      end

      private

      attr_reader :suggestions, :message_url
    end
  end
end
