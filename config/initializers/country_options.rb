# frozen_string_literal: true

module CountryOptions
  class << self
    def list
      @list ||= compute_list
    end

    private

    def compute_list
      ISO3166::Country.all
        .reject { |country| %w[IL KP].include?(country.alpha2) }
        .map do |country|
          country.common_name || country.official_name || country.translations['en'] || country.alpha2
        end
        .compact
        .uniq
        .sort
    end
  end
end

COUNTRY_OPTIONS = CountryOptions.list
