# frozen_string_literal: true

module HotelPortal
  module Reports
    # Turns report records into export rows for the visible columns only. The
    # caller gives a lambda that returns the cell values of one column.
    class ColumnExportTable
      attr_reader :columns

      def initialize(records:, columns:, visible_columns:, values:)
        @records = records
        @columns = columns.selected(visible_columns)
        @values = values
        raise ArgumentError, "at least one visible column is required" if @columns.empty?
      end

      def headers = columns.flat_map(&:export_labels)
      def pdf_headers = columns.map(&:pdf_label)
      def excel_widths = columns.flat_map { |column| Array.new(column.export_labels.size, column.excel_width) }
      def column_types = columns.flat_map { |column| Array.new(column.export_labels.size, column.type) }
      def rows = @records.map { |record| values_for(record, pdf: false) }
      def pdf_rows = @records.map { |record| values_for(record, pdf: true) }
      def money_indexes = column_types.each_index.select { |index| column_types[index] == :money }
      def pdf_money_indexes = columns.each_index.select { |index| columns[index].type == :money }

      def pdf_widths(total_width = nil)
        return columns.map(&:pdf_width) if total_width.nil?

        preferred = columns.sum(&:pdf_width).to_f
        columns.map { |column| column.pdf_width * total_width / preferred }
      end

      # Builds the total line of a currency. Every key of totals that matches a
      # column key lands under that column. The first cell names the total.
      def total_row(totals, pdf: false)
        row = Array.new((pdf ? pdf_headers : headers).size)
        row[0] = "TOTAL #{totals.fetch(:currency)}"
        index = 0
        columns.each do |column|
          key = column.key.to_sym
          row[index] = totals[key] if totals.key?(key)
          index += pdf ? 1 : column.export_labels.size
        end
        row
      end

      private

      def values_for(record, pdf:)
        columns.flat_map do |column|
          value = @values.call(record, column.key, pdf)
          value.is_a?(Array) ? value : [ value ]
        end
      end
    end
  end
end
