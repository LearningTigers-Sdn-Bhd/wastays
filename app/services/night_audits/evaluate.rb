module NightAudits
  class Evaluate
    PRE_CLOSE_CHECKS = [
      Evaluation::Checks::DueOuts,
      Evaluation::Checks::BookingTimestamps,
      Evaluation::Checks::MissingFolios,
      Evaluation::Checks::OutstandingFolioBalances,
      Evaluation::Checks::UnsyncedPayments,
      Evaluation::Checks::UnsyncedRefunds
    ].freeze
    POST_CLOSE_CHECKS = [
      Evaluation::Checks::DueOuts,
      Evaluation::Checks::BookingTimestamps,
      Evaluation::Checks::MissingFolios,
      Evaluation::Checks::MissingNightlyCharges,
      Evaluation::Checks::OutstandingFolioBalances,
      Evaluation::Checks::UnsyncedPayments,
      Evaluation::Checks::UnsyncedRefunds
    ].freeze
    WARNINGS = [
      Evaluation::Warnings::DetectedBookingStatuses,
      Evaluation::Warnings::OpenOperationalRequests,
      Evaluation::Warnings::UnusualFolioBalances
    ].freeze

    def initialize(hotel:, business_date:, phase: :post_close)
      @hotel = hotel
      @business_date = business_date
      @phase = phase
    end

    def call
      context = Evaluation::Context.new(hotel: @hotel, business_date: @business_date, phase: @phase)

      Evaluation::Result.new(
        blocked_details: build_results(checks_for(context), context),
        exceptions: build_results(WARNINGS, context),
        summary: Evaluation::BuildSummary.new(context: context).call
      ).to_h
    end

    private

    def checks_for(context)
      context.post_close? ? POST_CLOSE_CHECKS : PRE_CLOSE_CHECKS
    end

    def build_results(services, context)
      services.each_with_object({}) do |service, results|
        results.merge!(service.new(context: context).call)
      end
    end
  end
end
