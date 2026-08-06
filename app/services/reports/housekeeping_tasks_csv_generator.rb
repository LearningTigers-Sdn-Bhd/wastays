# frozen_string_literal: true

module Reports
  class HousekeepingTasksCsvGenerator
    def initialize(room_groups:)
      @table = HousekeepingTasksExportTable.new(room_groups: room_groups)
      @csv = HotelPortal::Reports::Exports::CsvReportSupport.new
    end

    def call
      @csv.generate do |csv|
        csv << HousekeepingTasksExportTable::HEADERS
        @table.rows.each { |row| csv << formatted_row(row) }
      end
    end

    private

    def formatted_row(row)
      row.each_with_index.map do |value, index|
        case HousekeepingTasksExportTable::COLUMN_TYPES[index]
        when :date then @csv.date(value)
        when :integer then value
        else @csv.text(value)
        end
      end
    end
  end
end
