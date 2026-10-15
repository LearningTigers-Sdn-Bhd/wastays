# frozen_string_literal: true

module Reports
  # Writes a money amount in English words, as agents and accounts teams in Malaysia
  # expect it under a total: "Two thousand two hundred and eighty ringgit only".
  module AmountInWords
    ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen
      fourteen fifteen sixteen seventeen eighteen nineteen].freeze
    TENS = %w[_ _ twenty thirty forty fifty sixty seventy eighty ninety].freeze
    SCALES = [ [ 1_000_000_000, "billion" ], [ 1_000_000, "million" ], [ 1_000, "thousand" ] ].freeze
    UNITS = { "MYR" => %w[ringgit sen] }.freeze

    module_function

    def call(amount, currency:)
      cents = (amount.to_d.abs * 100).round.to_i
      major, minor = cents.divmod(100)
      major_unit, minor_unit = UNITS.fetch(currency.to_s.upcase) { [ currency.to_s.upcase, "cents" ] }

      text = "#{words(major)} #{major_unit}"
      text += " and #{words(minor)} #{minor_unit}" if minor.positive?
      "#{text} only".upcase_first
    end

    def words(number)
      return ONES[number] if number < 20
      return [ TENS[number / 10], (ONES[number % 10] if (number % 10).positive?) ].compact.join("-") if number < 100
      return hundreds(number) if number < 1_000

      scale, name = SCALES.find { |value, _| number >= value }
      head, rest = number.divmod(scale)
      [ "#{words(head)} #{name}", remainder(rest) ].compact.join(" ")
    end

    def hundreds(number)
      head, rest = number.divmod(100)
      [ "#{ONES[head]} hundred", (("and " + words(rest)) if rest.positive?) ].compact.join(" ")
    end

    # "One thousand and five", but "one thousand two hundred".
    def remainder(rest)
      return if rest.zero?

      rest < 100 ? "and #{words(rest)}" : words(rest)
    end
  end
end
