# frozen_string_literal: true

module Reports
  class HousekeepingTasksCsvGenerator
    def initialize(rooms:, visible_columns:)
      @table = HousekeepingTasksExportTable.new(rooms:, visible_columns:)
      @csv = HotelPortal::Reports::Exports::CsvReportSupport.new
    end

    def call
      @csv.generate do |csv|
        csv << @table.headers
        @table.rows.each { |row| csv << formatted_row(row) }
      end
    end

    private

    def formatted_row(row)
      row.each_with_index.map do |value, index|
        case @table.column_types[index]
        when :date then @csv.date(value)
        when :integer then value
        else @csv.text(value)
        end
      end
    end
  end
end
