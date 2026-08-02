# frozen_string_literal: true

module NightAudits
  class RecalculateFinancialSummary
    def initialize(hotel:, business_date:, user:, reason:)
      @implementation = Financials::RecalculateSummary.new(
        hotel: hotel,
        business_date: business_date,
        user: user,
        reason: reason
      )
    end

    delegate :call, to: :@implementation
  end
end
