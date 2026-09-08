# frozen_string_literal: true

module HotelPortal
  # Reads the Getting Around columns back as short guest-facing phrases.
  # The sheets keep the numbers apart, so the read view is the only place that
  # joins a distance to a travel time or a price to its unit.
  module TransportDetailsHelper
    def travel_summary(distance_km, travel_minutes)
      parts = []
      parts << "#{travel_minutes} min" if travel_minutes.present?
      parts << "#{distance_km} km" if distance_km.present?
      return if parts.empty?

      safe_join(parts.map { |part| tag.span(part, class: "block") })
    end

    def transfer_price_summary(detail, hotel)
      return "Free" if detail.airport_transfer_offered? && detail.airport_transfer_price&.zero?
      return if detail.airport_transfer_price.blank?

      format_currency(detail.airport_transfer_price, currency: hotel.default_currency)
    end

    def lead_time_summary(hours)
      return if hours.blank?
      return "No notice needed" if hours.zero?

      pluralize(hours, "hour")
    end

    def parking_price_summary(detail, hotel)
      return unless detail.parking?
      return "Free" if detail.parking_price_unit == "free" || detail.parking_price&.zero?
      return if detail.parking_price.blank?

      price = format_currency(detail.parking_price, currency: hotel.default_currency)
      unit = detail.price_unit_label
      unit.present? ? "#{price} #{unit.downcase}" : price
    end

    def height_limit_summary(metres)
      return if metres.blank?

      "#{number_with_precision(metres, precision: 2, strip_insignificant_zeros: true)} m"
    end

    def yes_no(flag)
      flag ? "Yes" : "No"
    end
  end
end
