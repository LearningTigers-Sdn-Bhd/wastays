# frozen_string_literal: true

module GuestIdentityDocuments
  # Maps the old "ic" document type onto the two types LHDN needs to tell
  # apart: a Malaysian MyKad and a foreign national identity card.
  #
  # Only "ic" reads the country. A value that is already canonical stays as it
  # is, so a later edit to an unrelated field never rewrites a stored identity.
  class NormalizeType
    CANONICAL_TYPES = %w[malaysian_nric national_id passport].freeze

    def self.call(value:, country:)
      normalized = value.to_s.downcase.strip
      return normalized if CANONICAL_TYPES.include?(normalized)
      return unless normalized == "ic"

      country.blank? || malaysia?(country) ? "malaysian_nric" : "national_id"
    end

    def self.country_code(country)
      return "MYS" if malaysia?(country)

      ISO3166::Country.find_country_by_any_name(country.to_s)&.alpha3
    rescue StandardError
      nil
    end

    def self.malaysia?(country)
      country.to_s.casecmp?("Malaysia") || country.to_s.upcase.in?(%w[MY MYS])
    end

    private_class_method :malaysia?
  end
end
