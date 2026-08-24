# frozen_string_literal: true

require "cgi"
require "uri"

module Attractions
  class GoogleMapsUrlParser
    Result = ApplicationResult.define(:parsed)
    Parsed = Data.define(
      :name,
      :normalized_name,
      :latitude,
      :longitude,
      :google_maps_url,
      :fingerprint
    )

    APPROVED_HOSTS = %w[google.com www.google.com maps.google.com].freeze
    NUMBER_PATTERN = "-?\\d+(?:\\.\\d+)?"
    PLACE_PATTERN = %r{/maps/place/([^/?#]+)}i
    DATA_COORDINATE_PATTERN = /!3d(#{NUMBER_PATTERN})!4d(#{NUMBER_PATTERN})/i
    VIEW_COORDINATE_PATTERN = /@(#{NUMBER_PATTERN}),(#{NUMBER_PATTERN})(?:,|\/|\?|#|$)/i

    def self.call(url)
      new(url).call
    end

    def initialize(url)
      @url = url.to_s.strip
    end

    def call
      uri = parse_uri
      return Result.failure("Enter a full Google Maps browser URL.") unless valid_google_uri?(uri)

      name = extract_name(uri)
      return Result.failure("The Google Maps URL does not contain a place name.") if name.blank?

      coordinates = extract_coordinates(uri)
      return Result.failure("The Google Maps URL does not contain valid coordinates.") unless coordinates

      latitude, longitude = coordinates.map { |value| BigDecimal(value) }
      return Result.failure("The latitude must be between -90 and 90.") unless latitude.between?(-90, 90)
      return Result.failure("The longitude must be between -180 and 180.") unless longitude.between?(-180, 180)

      normalized_name = Fingerprint.normalize_name(name)
      parsed = Parsed.new(
        name: name,
        normalized_name: normalized_name,
        latitude: latitude,
        longitude: longitude,
        google_maps_url: @url,
        fingerprint: Fingerprint.call(name: name, latitude: latitude, longitude: longitude)
      )

      Result.success(parsed: parsed)
    rescue URI::InvalidURIError, ArgumentError
      Result.failure("Enter a valid Google Maps browser URL.")
    end

    private

    def parse_uri
      URI.parse(@url)
    end

    def valid_google_uri?(uri)
      uri.is_a?(URI::HTTPS) && APPROVED_HOSTS.include?(uri.host&.downcase) && uri.userinfo.nil? && uri.port == 443
    end

    def extract_name(uri)
      match = uri.path.match(PLACE_PATTERN)
      return unless match

      CGI.unescape(match[1]).tr("+", " ").squish.presence
    end

    def extract_coordinates(uri)
      data_matches = @url.scan(DATA_COORDINATE_PATTERN)
      return data_matches.last if data_matches.any?

      @url.scan(VIEW_COORDINATE_PATTERN).last
    end
  end
end
