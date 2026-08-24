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

    def self.call(fingerprint:)
      return if fingerprint.blank?

      Attraction.where(coordinate_fingerprint: fingerprint)
        .order(Arel.sql(STATUS_ORDER), :id)
        .first
    end
  end
end
