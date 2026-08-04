# frozen_string_literal: true

module Discounts
  class Description
    def self.call(discount:, currency:, quote:, submitted_description: nil)
      detail = submitted_description.to_s.strip.presence
      return [ discount.name, detail ].compact.join(" · ") if discount.manual?

      calculation = if discount.percentage?
        "#{discount.formatted_rate}% of #{discount.application_scope_label.downcase} (#{currency} #{format('%.2f', quote.base_amount)})"
      else
        "#{discount.application_scope_label}"
      end
      [ discount.name, calculation, detail ].compact.join(" · ")
    end
  end
end
