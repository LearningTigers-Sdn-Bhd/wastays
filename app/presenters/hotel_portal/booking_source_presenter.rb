# frozen_string_literal: true

module HotelPortal
  class BookingSourcePresenter
    def initialize(source)
      @raw = source.to_s
      @record = BookingSource.find_by_source(source)
    end

    def label
      @record&.label || (@raw.presence&.tr("_", " ")&.titleize || "Unknown")
    end

    def icon
      @record&.icon.presence || "link"
    end

    def ota?
      @record&.kind == "ota"
    end

    def logo
      @record&.logo if @record&.logo&.attached?
    end

    def badge_color
      @record&.badge_color
    end

    def badge_text_color
      @record&.badge_text_color || "#FFFFFF"
    end

    def badge_initial
      @record&.badge_initial
    end

    def self.normalize(source)
      BookingSource.normalize(source)
    end

    def self.manual_options
      BookingSource.manual_options
    end

    def self.ota_options
      BookingSource.ota_options
    end

    def self.other_channel_options
      BookingSource.other_channel_options
    end
  end
end
