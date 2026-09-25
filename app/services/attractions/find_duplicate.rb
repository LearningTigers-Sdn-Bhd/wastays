# frozen_string_literal: true

module Attractions
  class FindDuplicate
    STATUS_ORDER = <<~SQL.squish.freeze
      CASE status
      WHEN 'approved' THEN 0
      WHEN 'pending' THEN 1
      WHEN 'rejected' THEN 2
      ELSE 3
      END
    SQL

    def self.call(fingerprint:, google_maps_url: nil)
      return if fingerprint.blank? && google_maps_url.blank?

      matches = Attraction.none
      matches = matches.or(Attraction.where(coordinate_fingerprint: fingerprint)) if fingerprint.present?
      matches = matches.or(Attraction.where(google_maps_url: google_maps_url)) if google_maps_url.present?
      matches.order(Arel.sql(STATUS_ORDER), :id).first
    end
  end
end
