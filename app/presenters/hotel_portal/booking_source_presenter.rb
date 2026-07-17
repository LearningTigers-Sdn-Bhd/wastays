# frozen_string_literal: true

module HotelPortal
  class BookingSourcePresenter
    SOURCE_ICONS = {
      "phone" => "phone",
      "walk_in" => "user",
      "email" => "mail",
      "whatsapp" => "message-circle",
      "internal" => "building-2",
      "staff" => "building-2",
      "direct" => "building-2",
      "manual_at_hotel" => "building-2",
      "booking_com" => "globe",
      "agoda" => "globe",
      "expedia" => "globe",
      "traveloka" => "globe",
      "ota" => "globe",
      "channel_manager" => "globe"
    }.freeze

    def initialize(source)
      @source = source.to_s.downcase
    end

    def label
      @source.presence&.tr("_", " ")&.titleize || "Unknown"
    end

    def icon
      SOURCE_ICONS.fetch(@source, "link")
    end
  end
end
