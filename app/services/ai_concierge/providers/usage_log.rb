# frozen_string_literal: true

module AiConcierge
  module Providers
    # What a turn cost, written down.
    #
    # Nothing in this namespace counted a token until now, which is how gemini
    # billed its thinking silently for months. Prompt caching is the same shape
    # of problem in reverse: it is invisible when it works and equally
    # invisible when it stops, and it stops the moment the prompt prefix drops
    # below a provider's minimum -- no error, no failure, just a bigger bill
    # and a slower reply.
    #
    # A log line is the whole mechanism on purpose. Nobody has asked to see
    # cost per thread, and a column would have to be designed before it could
    # be wrong.
    class UsageLog
      def self.call(response, hotel:, stage:)
        new(response, hotel: hotel, stage: stage).call
      end

      def initialize(response, hotel:, stage:)
        @response = response
        @hotel = hotel
        @stage = stage
      end

      # Every eval fixture runs through here behind a ScriptedChat whose
      # response is a two-field Struct, so a response that cannot report usage
      # is the normal case in test, not an error. Same guard RunTurn already
      # applies to `content`.
      def call
        return unless response.respond_to?(:input_tokens)

        Rails.logger.info(
          "AiConcierge::Usage #{stage} provider=#{hotel.ai_provider_name} " \
          "model=#{hotel.ai_concierge_model_name} " \
          "in=#{response.input_tokens} out=#{response.output_tokens} " \
          "cached=#{response.cached_tokens}"
        )
      end

      private

      attr_reader :response, :hotel, :stage
    end
  end
end
