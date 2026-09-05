# frozen_string_literal: true

module AiConcierge
  module MessageBuilders
    class GreetingBuilder < BaseBuilder
      def call(reply_type)
        return unless reply_type.to_sym == :greeting

        "Hello! Welcome to #{hotel.name}. I can help you find the right stay, check prices, " \
          "answer hotel questions, or access an existing booking. What can I help you with today?"
      end
    end
  end
end
