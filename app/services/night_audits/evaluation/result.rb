module NightAudits
  module Evaluation
    class Result
      attr_reader :blocked_details, :exceptions, :summary

      def initialize(blocked_details:, exceptions:, summary:)
        @blocked_details = blocked_details
        @exceptions = exceptions
        @summary = summary
      end

      def to_h
        {
          blocked_details: blocked_details,
          exceptions: exceptions,
          summary: summary
        }
      end
    end
  end
end
