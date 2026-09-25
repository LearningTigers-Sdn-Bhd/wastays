# frozen_string_literal: true

module Bookings
  # The ages of the children in one room, as the pricing engine reads them.
  #
  # An age-banded rate plan can only price a child whose age it knows, so every
  # channel that books or re-prices a room passes these through. They are kept
  # only when there is exactly one age per child: a partial list cannot say
  # which child is which, and pricing falls back to the plan's child multiplier
  # rather than guessing.
  module ChildAges
    module_function

    # Accepts an array (["8", 14]) or the desk's typed list ("8, 14").
    def normalize(raw, children)
      ages = parse(raw)
      return [] if ages.nil? || ages.size != children.to_i

      ages.map { |age| age.clamp(RatePlanAgeBand::AGE_RANGE.min, RatePlanAgeBand::AGE_RANGE.max) }
    end

    def parse(raw)
      values = raw.is_a?(String) ? raw.split(/[\s,]+/) : Array(raw)
      ages = values.map(&:to_s).map(&:strip).compact_blank.map { |value| Integer(value, 10, exception: false) }
      ages.all? ? ages : nil
    end
  end
end
