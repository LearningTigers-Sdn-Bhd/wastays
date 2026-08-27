# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Sales
      # Reads a refusal only while an optional sales offer awaits an answer.
      class OfferRefusalPolicy
        Result = Data.define(:refusal, :standalone) do
          def refusal? = refusal
          def standalone? = standalone
        end

        PREFIXES = [
          "not interested", "no thanks", "not now", "no",
          "tidak berminat", "tak mahu", "tidak", "tak",
          "不用", "不要", "不"
        ].freeze

        def initialize(message:, sales_task:)
          @message = message.to_s
          @sales_task = sales_task.is_a?(Hash) ? sales_task : {}
        end

        def call
          return Result.new(refusal: false, standalone: false) if sales_task["last_optional_action"].blank?

          prefix = PREFIXES.find { |candidate| normalized == candidate || normalized.start_with?("#{candidate} ") }
          Result.new(refusal: prefix.present?, standalone: prefix.present? && standalone_refusal?)
        end

        private

        attr_reader :message, :sales_task

        def normalized
          @normalized ||= message.downcase.gsub(/[^\p{Alnum}'’]+/u, " ").squish
        end

        def standalone_refusal?
          Core::ConfirmationReader.new(message: message).confirmation == "no" || PREFIXES.include?(normalized)
        end
      end
    end
  end
end
