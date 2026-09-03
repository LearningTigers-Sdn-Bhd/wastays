# frozen_string_literal: true

module AiConcierge
  module Matching
    # Matches a greeting only when it is the guest's whole message.
    class GreetingMatcher
      GREETINGS = [
        "hello", "hi", "hey", "hello there", "hi there", "hey there", "hello again", "hi again",
        "good morning", "good afternoon", "good evening",
        "hai", "helo", "salam", "salam sejahtera", "selamat pagi", "selamat petang", "selamat malam",
        "assalamualaikum",
        "你好", "您好", "嗨", "早安", "早上好", "下午好", "晚上好"
      ].freeze
      WAVE_ONLY = /\A(?:👋[\u{1F3FB}-\u{1F3FF}]?)+\z/

      def initialize(message:)
        @message = message.to_s
      end

      def standalone?
        wave_only? || GREETINGS.include?(normalized)
      end

      private

      attr_reader :message

      def normalized
        @normalized ||= message.unicode_normalize(:nfkc).downcase.gsub(/[^\p{L}\p{N}]+/, " ").squish
      end

      def wave_only?
        message.gsub(/\s+/, "").match?(WAVE_ONLY)
      end
    end
  end
end
