# frozen_string_literal: true

module HotelPortal
  module Reports
    module BookingSourceLabel
      LABELS = {
        "walk_in" => "Walk-in",
        "agoda" => "Agoda",
        "whatsapp" => "WhatsApp",
        "corporate" => "Corporate",
        "internal" => "Direct"
      }.freeze

      module_function

      def normalize(source)
        key = source.to_s.strip
        key = "unknown" if key.empty?
        LABELS[key] || key.titleize.presence || "Others"
      end
    end
  end
end
