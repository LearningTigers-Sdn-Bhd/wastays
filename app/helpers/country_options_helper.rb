module CountryOptionsHelper
  def country_options
    CountryOptions.list
  end
end
