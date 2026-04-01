module CountryOptionsHelper
  def country_options
    return ::CountryOptions.list if defined?(::CountryOptions)

    @country_options ||= begin
      require "countries"
      list = ::ISO3166::Country.all
        .reject { |country| %w[IL KP].include?(country.alpha2) }
        .map do |country|
          country.common_name || country.official_name || country.translations["en"] || country.alpha2
        end
        .compact
        .uniq
        .sort
      list |= [ "China" ]
      list
    rescue LoadError
      []
    end
  end
end
