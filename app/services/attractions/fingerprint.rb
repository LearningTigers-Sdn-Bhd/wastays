# frozen_string_literal: true

require "digest"

module Attractions
  class Fingerprint
    DECIMAL_PLACES = 5

    def self.call(name:, latitude:, longitude:)
      normalized_name = normalize_name(name)
      coordinates = [ latitude, longitude ].map { |value| format("%.#{DECIMAL_PLACES}f", value.to_d) }
      Digest::SHA256.hexdigest([ normalized_name, *coordinates ].join("|"))
    end

    def self.normalize_name(name)
      name.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{Alnum}]+/u, " ").squish
    end
  end
end
