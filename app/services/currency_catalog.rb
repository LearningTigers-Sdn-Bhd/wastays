# frozen_string_literal: true

class CurrencyCatalog
  COMMON_CODES = %w[MYR USD SGD JPY GBP EUR AUD CNY].freeze
  ZERO_DECIMAL_CODES = %w[BIF CLP DJF GNF JPY KMF KRW MGA PYG RWF UGX VND VUV XAF XOF XPF].freeze
  SYMBOLS = {
    "MYR" => "RM",
    "USD" => "$",
    "SGD" => "S$",
    "JPY" => "¥",
    "GBP" => "£",
    "EUR" => "€",
    "AUD" => "A$",
    "CNY" => "¥"
  }.freeze
  NAMES = {
    "MYR" => "Malaysian Ringgit",
    "USD" => "US Dollar",
    "SGD" => "Singapore Dollar",
    "JPY" => "Japanese Yen",
    "GBP" => "Pound Sterling",
    "EUR" => "Euro",
    "AUD" => "Australian Dollar",
    "CNY" => "Chinese Yuan",
    "CAD" => "Canadian Dollar",
    "CHF" => "Swiss Franc",
    "HKD" => "Hong Kong Dollar",
    "NZD" => "New Zealand Dollar",
    "KRW" => "South Korean Won",
    "INR" => "Indian Rupee",
    "IDR" => "Indonesian Rupiah",
    "THB" => "Thai Baht",
    "PHP" => "Philippine Peso",
    "VND" => "Vietnamese Dong",
    "TWD" => "New Taiwan Dollar",
    "MOP" => "Macau Pataca"
  }.freeze

  Currency = Struct.new(:code, :label, :symbol, :precision, keyword_init: true)

  class << self
    def codes
      @codes ||= currencies.map(&:code)
    end

    def currencies
      @currencies ||= begin
        discovered_codes = ISO3166::Country.all.filter_map(&:currency_code).uniq.sort
        sorted_codes = COMMON_CODES + (discovered_codes - COMMON_CODES)

        sorted_codes.map do |code|
          Currency.new(
            code: code,
            label: label_for(code),
            symbol: symbol_for(code),
            precision: precision_for(code)
          )
        end
      end
    end

    def options
      currencies.map { |currency| [ currency.label, currency.code ] }
    end

    def valid?(code)
      codes.include?(normalize(code))
    end

    def normalize(code, fallback: "MYR")
      normalized = code.to_s.upcase.strip
      normalized.presence || fallback
    end

    def find(code)
      currencies.find { |currency| currency.code == normalize(code) }
    end

    def symbol_for(code)
      SYMBOLS[normalize(code)] || normalize(code)
    end

    def precision_for(code)
      ZERO_DECIMAL_CODES.include?(normalize(code)) ? 0 : 2
    end

    def label_for(code)
      normalized = normalize(code)
      currency_name = NAMES[normalized]

      if currency_name.present?
        "#{normalized} - #{currency_name}"
      else
        normalized
      end
    end

    private

    # Keeping this for potential future internal use, but removing from labels
    def country_names_for(code)
      @country_names_cache ||= {}
      @country_names_cache[code] ||= ISO3166::Country.all
                                     .select { |c| c.currency_code == code }
                                     .map(&:common_name)
                                     .uniq
                                     .first(3)
    end  end
end
