# frozen_string_literal: true

module Ezee
  # Reads the boat transfer a property's staff type into a reservation remark,
  # e.g. "(1) BOAT IN : 1030 / BOAT OUT : OWN BOAT".
  #
  # The rule is the property's own: a time on its own is the resort boat, "OWN
  # BOAT" is the guest's own, and a time marked "(CHARTER)" is a charter. The
  # spellings vary (a slash or a newline between the halves, "1030" or "10:30",
  # "BOAT IN TIME"), so this reads what it recognises and leaves the rest alone:
  # an unreadable half is nil, never a guess. The remark itself is always kept
  # by the caller, so a missed parse loses nothing.
  class BoatRemark
    Transfer = Struct.new(:type, :time, keyword_init: true)

    IN_PATTERN = /BOAT\s*IN(?:\s*TIME)?\s*:?\s*(.*?)(?=BOAT\s*OUT|\z)/mi
    OUT_PATTERN = /BOAT\s*OUT(?:\s*TIME)?\s*:?\s*(.*)\z/mi
    TIME = /(?<![\d:])([01]?\d|2[0-3]):?([0-5]\d)(?![\d:])/

    def self.call(text) = new(text).call

    def initialize(text)
      @text = text.to_s
    end

    # { boat_in: Transfer | nil, boat_out: Transfer | nil }
    def call
      { boat_in: transfer(@text[IN_PATTERN, 1]), boat_out: transfer(@text[OUT_PATTERN, 1]) }
    end

    private

    def transfer(fragment)
      value = fragment.to_s.strip
      return nil if value.blank?

      time = clock_time(value)
      return Transfer.new(type: "own", time: nil) if value.match?(/\bown\b/i)
      return Transfer.new(type: "charter", time: time) if value.match?(/charter/i)
      return nil if time.nil?

      Transfer.new(type: "provided", time: time)
    end

    def clock_time(value)
      match = value.match(TIME)
      return nil unless match

      format("%02d:%s", match[1].to_i, match[2])
    end
  end
end
