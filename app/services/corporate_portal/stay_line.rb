# frozen_string_literal: true

module CorporatePortal
  # One line of an agent's stay: some number of rooms of one category, on one rate,
  # each with the same occupancy. A stay is a list of these, so an agent can book a
  # Deluxe King for two adults and a Standard Family for four -- different
  # categories, rates and parties -- under one group, on the same dates.
  #
  # Lines travel in the URL while the agent builds the stay, as an indexed hash
  # (lines[0][room_type_id], ...) with child ages as one comma-separated value, so
  # Back and reload keep the whole cart.
  StayLine = Struct.new(:room_type_id, :rate_plan_id, :adults, :children, :child_ages, :quantity, keyword_init: true) do
    # `raw` is whatever the request carried: an indexed hash (the form and URL
    # shape) or an array of hashes. Anything that names no room category is
    # dropped, so an empty or half-typed line never reaches the quote.
    def self.parse(raw)
      entries = raw.is_a?(Hash) || raw.respond_to?(:to_unsafe_h) ? raw.to_h.sort_by { |index, _| index.to_s.to_i }.map(&:last) : Array(raw)
      entries.filter_map do |entry|
        attrs = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry.to_h
        attrs = attrs.symbolize_keys
        next if attrs[:room_type_id].blank?

        build(attrs)
      end
    end

    def self.build(attrs)
      children = [ attrs[:children].to_i, 0 ].max
      new(
        room_type_id: attrs[:room_type_id].to_i,
        rate_plan_id: attrs[:rate_plan_id].presence&.to_i,
        # Not floored: a party of nobody is refused at the quote, never booked as one.
        adults: [ attrs[:adults].to_i, 0 ].max,
        children: children,
        child_ages: ages(attrs[:child_ages]).first(children),
        quantity: [ attrs[:quantity].to_i, 1 ].max
      )
    end

    def self.ages(value)
      values = value.is_a?(String) ? value.split(",") : Array(value)
      values.compact_blank.map(&:to_i)
    end

    # The shape that goes back into a URL or a hidden field.
    def to_param_hash
      {
        room_type_id: room_type_id, rate_plan_id: rate_plan_id, adults: adults, children: children,
        child_ages: child_ages.join(","), quantity: quantity
      }.compact
    end

    # Lines priced the same way can share one quote.
    def occupancy = [ adults, children, child_ages, quantity ]

    def self.to_params(lines) = lines.each_with_index.to_h { |line, index| [ index.to_s, line.to_param_hash ] }
  end
end
