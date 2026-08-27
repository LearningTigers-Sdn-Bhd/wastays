# frozen_string_literal: true

module EInvoice
  # LHDN's recommended MSIC codes for the kinds of accommodation businesses on
  # this platform (see https://sdk.myinvois.hasil.gov.my/codes/msic-codes/ for
  # the full list). Not exhaustive - a hotel whose activity isn't one of these
  # still types its own code and description directly.
  module MsicCodes
    CUSTOM = "custom"

    CODES = {
      "55101" => "Hotels and resort hotels",
      "55103" => "Apartment hotels / Serviced apartments",
      "55108" => "Home stay operations",
      "55109" => "Other short term accommodation activities"
    }.freeze

    def self.description_for(code)
      CODES[code.to_s]
    end

    # For a select: known codes first, "Custom" sentinel last.
    def self.options
      CODES.map { |code, description| [ "#{code} — #{description}", code ] } +
        [ [ "Custom", CUSTOM ] ]
    end
  end
end
