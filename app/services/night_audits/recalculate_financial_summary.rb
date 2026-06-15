module NightAudits
  class RecalculateFinancialSummary
    def initialize(hotel:, business_date:, user:, reason:)
      @hotel = hotel
      @business_date = business_date.to_date
      @user = user
      @reason = reason
    end

    def call
      night_audit = @hotel.night_audits.find_by(business_date: @business_date, status: "completed")
      return unless night_audit

      new_totals = calculate_new_totals
      summary = night_audit.financial_summary || night_audit.build_financial_summary

      if totals_changed?(summary, new_totals)
        previous_values = summary.attributes.slice(*new_totals.keys.map(&:to_s))

        summary.assign_attributes(new_totals)
        summary.log_change(
          user: @user,
          previous_values: previous_values,
          new_values: new_totals,
          reason: @reason
        )
        summary.save!
      end
    end

    private

    def calculate_new_totals
      NightAudits::CalculateFinancialSummary.call(hotel: @hotel, business_date: @business_date)
    end

    def totals_changed?(summary, new_totals)
      new_totals.any? { |k, v| summary.public_send(k).to_d != v.to_d }
    end
  end
end
