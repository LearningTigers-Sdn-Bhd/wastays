# frozen_string_literal: true

module HotelPortal
  module Reports
    # Builds the column module that a report table uses for its column picker,
    # its exports, and its saved view preference.
    module ReportColumns
      Column = Data.define(:key, :label, :export_labels, :pdf_label, :pdf_width, :excel_width, :type) do
        def initialize(type: :text, **) = super
      end

      module_function

      def column(**attributes) = Column.new(**attributes)

      def build(columns:, defaults:)
        keys = columns.map(&:key).freeze
        unknown = defaults - keys
        raise ArgumentError, "unknown default columns: #{unknown.join(', ')}" if unknown.any?

        Module.new do
          const_set(:ALL, columns.freeze)
          const_set(:KEYS, keys)
          const_set(:DEFAULT_KEYS, defaults.freeze)
          const_set(:BY_KEY, columns.index_by(&:key).freeze)

          def self.normalize(wanted)
            requested = Array(wanted).map(&:to_s)
            self::KEYS.select { |key| requested.include?(key) }
          end

          def self.selected(wanted)
            normalize(wanted).map { |key| self::BY_KEY.fetch(key) }
          end
        end
      end
    end
  end
end
