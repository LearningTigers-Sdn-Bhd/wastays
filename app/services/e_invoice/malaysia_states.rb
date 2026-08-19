# frozen_string_literal: true

module EInvoice
  # LHDN's prescribed state codes. These are what MyInvois validates against -
  # a city name is not a substitute, which is why the buyer's state is captured
  # directly rather than inferred from whatever city they typed.
  #
  # "17" is LHDN's "Not Applicable", used for buyers outside Malaysia.
  module MalaysiaStates
    NOT_APPLICABLE = "17"

    CODES = {
      "01" => "Johor",
      "02" => "Kedah",
      "03" => "Kelantan",
      "04" => "Melaka",
      "05" => "Negeri Sembilan",
      "06" => "Pahang",
      "07" => "Pulau Pinang",
      "08" => "Perak",
      "09" => "Perlis",
      "10" => "Selangor",
      "11" => "Terengganu",
      "12" => "Sabah",
      "13" => "Sarawak",
      "14" => "Wilayah Persekutuan Kuala Lumpur",
      "15" => "Wilayah Persekutuan Labuan",
      "16" => "Wilayah Persekutuan Putrajaya",
      NOT_APPLICABLE => "Not applicable (outside Malaysia)"
    }.freeze

    # Kept so bookings captured before the state field existed still resolve,
    # rather than failing at submission time. New entry goes through the list.
    LEGACY_CITY_FALLBACK = {
      "johor bahru" => "01",
      "alor setar" => "02",
      "kota bharu" => "03",
      "melaka" => "04",
      "seremban" => "05",
      "kuantan" => "06",
      "george town" => "07",
      "georgetown" => "07",
      "ipoh" => "08",
      "kangar" => "09",
      "shah alam" => "10",
      "petaling jaya" => "10",
      "subang jaya" => "10",
      "klang" => "10",
      "kuala terengganu" => "11",
      "kota kinabalu" => "12",
      "sandakan" => "12",
      "tawau" => "12",
      "kuching" => "13",
      "miri" => "13",
      "sibu" => "13",
      "kuala lumpur" => "14",
      "labuan" => "15",
      "putrajaya" => "16"
    }.freeze

    def self.valid?(code)
      CODES.key?(code.to_s)
    end

    def self.name_for(code)
      CODES[code.to_s]
    end

    # For a select: [["Johor", "01"], ...] with Not Applicable last.
    def self.options
      CODES.except(NOT_APPLICABLE).map { |code, name| [ name, code ] }
           .sort_by(&:first) + [ [ CODES[NOT_APPLICABLE], NOT_APPLICABLE ] ]
    end

    # Resolution order: an explicit code always wins; a legacy city is a
    # best-effort rescue for records captured before the field existed.
    def self.resolve(state_code: nil, city: nil, country_code: nil)
      return state_code.to_s if valid?(state_code)
      return NOT_APPLICABLE if country_code.present? && country_code != "MYS"

      LEGACY_CITY_FALLBACK[city.to_s.strip.downcase]
    end
  end
end
