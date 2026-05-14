# frozen_string_literal: true

class DisplayCurrencyResolver
  COUNTRY_CURRENCY_OVERRIDES = {
    "MY" => "MYR",
    "US" => "USD",
    "GB" => "GBP",
    "JP" => "JPY"
  }.freeze

  def initialize(params:, cookies:, request:)
    @params = params
    @cookies = cookies
    @request = request
  end

  def call
    explicit_currency = supported_display_currency(params[:display_currency])
    return persist(explicit_currency) if explicit_currency.present?

    cookie_currency = supported_display_currency(cookies[:display_currency])
    return cookie_currency if cookie_currency.present?

    supported_display_currency(currency_for_country(country_code_from_ip)) || "MYR"
  end

  private

  attr_reader :params, :cookies, :request

  def persist(currency)
    cookies[:display_currency] = { value: currency, expires: 6.months.from_now, same_site: :lax }
    currency
  end

  def supported_display_currency(currency)
    code = CurrencyCatalog.normalize(currency, fallback: nil)
    return nil unless CurrencyCatalog.valid?(code)
    return code if code == "MYR"
    return code if ExchangeRate.active.exists?(currency_code: code)

    nil
  end

  def currency_for_country(country_code)
    return nil if country_code.blank?

    COUNTRY_CURRENCY_OVERRIDES[country_code] ||
      ISO3166::Country.find_country_by_alpha2(country_code)&.currency_code
  end

  def country_code_from_ip
    ip = client_ip
    return "MY" if ip.blank? || private_ip?(ip)

    Rails.cache.fetch("ip-country:#{ip}", expires_in: 12.hours) do
      lookup_country_code(ip)
    end
  end

  def lookup_country_code(ip)
    require "net/http"
    require "json"

    uri = URI("https://ipapi.co/#{ip}/json/")
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["country_code"]
  rescue StandardError
    nil
  end

  def client_ip
    request.headers["CF-Connecting-IP"] ||
      request.headers["X-Forwarded-For"]&.split(",")&.first&.strip ||
      request.remote_ip
  end

  def private_ip?(ip)
    require "ipaddr"
    addr = IPAddr.new(ip)
    addr.loopback? || addr.private?
  rescue IPAddr::InvalidAddressError
    false
  end
end
