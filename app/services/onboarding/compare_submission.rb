# frozen_string_literal: true

module Onboarding
  class CompareSubmission
    Result = ApplicationResult.define(:unchanged, :start_date, :end_date)

    def self.call(...) = new(...).call

    def self.coverage_dates(submission)
      coverage = submission.snapshot.fetch("rates").fetch("coverage")
      start_date = Date.iso8601(coverage.fetch("start_date"))
      end_date = Date.iso8601(coverage.fetch("end_date"))
      raise ArgumentError if end_date < start_date

      [ start_date, end_date ]
    rescue KeyError, TypeError, NoMethodError, ArgumentError
      raise ArgumentError, "This submission has missing or invalid availability dates. Request a new submission before continuing."
    end

    def initialize(hotel:, submission:)
      @hotel = hotel
      @submission = submission
    end

    def call
      start_date, end_date = self.class.coverage_dates(@submission)
      coverage = Rates::SetupCoverage.call(hotel: @hotel, start_date:, end_date:)
      current = SubmissionSnapshot.call(hotel: @hotel, rates_coverage: coverage)
      unchanged = ActiveSupport::SecurityUtils.secure_compare(current.digest, @submission.configuration_digest)
      Result.success(unchanged:, start_date:, end_date:)
    rescue ArgumentError => e
      Result.failure(e.message, unchanged: false, start_date: nil, end_date: nil)
    end
  end
end
