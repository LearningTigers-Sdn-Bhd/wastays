# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Sales
      # A commercial next step selected by Ruby, before any reply wording.
      class NextAction
        OPTIONAL_KINDS = %w[offer_booking_help offer_price_search offer_guided_hotel_exploration].freeze
        KINDS = %w[
          offer_booking_help
          offer_price_search
          offer_guided_hotel_exploration
          resume_booking
          continue_booking
          offer_alternative_search
          offer_front_desk
          none
        ].freeze

        def self.none = new("none")

        def initialize(kind)
          @kind = kind.to_s
          raise ArgumentError, "Unsupported next action: #{@kind}" unless KINDS.include?(@kind)

          freeze
        end

        attr_reader :kind

        def ==(other) = other.is_a?(self.class) && other.kind == kind
        alias eql? ==

        def hash = [ self.class, kind ].hash
        def none? = kind == "none"
        def optional? = OPTIONAL_KINDS.include?(kind)
        def to_s = kind
      end
    end
  end
end
