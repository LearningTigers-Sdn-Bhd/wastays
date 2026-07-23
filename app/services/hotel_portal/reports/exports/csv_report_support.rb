# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    module Exports
      class CsvReportSupport
        BOM = "\uFEFF"

        def generate(&block)
          BOM + CSV.generate(&block)
        end

        def text(value)
          CsvCellSanitizer.call(value)
        end

        def money(value)
          format("%.2f", value.to_d)
        end

        def date(value)
          value&.to_date&.iso8601
        end
      end
    end
  end
end
