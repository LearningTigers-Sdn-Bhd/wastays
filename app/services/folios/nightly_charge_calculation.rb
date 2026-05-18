# frozen_string_literal: true

module Folios
  module NightlyChargeCalculation
    extend ActiveSupport::Concern

    private

    def nightly_amount(total_amount, booking, business_date)
      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      return 0.to_d unless nights.positive?

      per_night = (total_amount.to_d / nights).round(2)
      return per_night unless business_date.to_date == booking.check_out.to_date - 1.day

      total_amount.to_d - (per_night * (nights - 1))
    end

    def tax_lines_for(booking)
      tax_lines = Array(booking.tax_lines)
      return tax_lines if tax_lines.any?

      return [] unless booking.tourism_tax_amount.to_d.positive?

      [ { "name" => "Tourism Tax", "amount" => booking.tourism_tax_amount, "type" => "tourism_tax" } ]
    end

    def tax_line_amount(tax_line)
      (tax_line["amount"].presence || tax_line[:amount]).to_d
    end

    def tax_line_name(tax_line)
      tax_line["name"].presence || tax_line[:name].presence || "Tax"
    end

    def tax_line_identity(tax_line, index)
      identity = tax_line["type"].presence || tax_line[:type].presence || tax_line_name(tax_line).parameterize.presence || "tax"
      "#{identity}:#{index}"
    end
  end
end
