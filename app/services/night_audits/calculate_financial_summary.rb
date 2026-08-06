# frozen_string_literal: true

module NightAudits
  class CalculateFinancialSummary
    def self.call(hotel:, business_date:)
      Financials::CalculateSummary.call(hotel: hotel, business_date: business_date)
    end

    def initialize(hotel:, business_date:)
      @implementation = Financials::CalculateSummary.new(hotel: hotel, business_date: business_date)
    end

    delegate :call, to: :@implementation
  end
end
