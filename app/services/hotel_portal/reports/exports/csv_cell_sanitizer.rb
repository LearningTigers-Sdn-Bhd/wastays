# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      class CsvCellSanitizer
        DANGEROUS_PREFIX = /\A[=+\-@\t\r]/

        def self.call(value)
          return if value.nil?

          text = value.to_s
          text.match?(DANGEROUS_PREFIX) ? "'#{text}" : text
        end
      end
    end
  end
end
