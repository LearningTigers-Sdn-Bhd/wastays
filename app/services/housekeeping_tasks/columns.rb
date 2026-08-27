# frozen_string_literal: true

module HousekeepingTasks
  module Columns
    Column = Data.define(:key, :label, :export_label, :pdf_label, :type, :pdf_width, :excel_width)

    ALL = [
      Column.new(key: "room_number", label: "Room", export_label: "Room Number", pdf_label: "Room", type: :text, pdf_width: 48, excel_width: 15),
      Column.new(key: "room_type", label: "Room type", export_label: "Room Type", pdf_label: "Room Type", type: :text, pdf_width: 80, excel_width: 22),
      Column.new(key: "room_group", label: "Room group", export_label: "Room Group", pdf_label: "Room Group", type: :text, pdf_width: 80, excel_width: 22),
      Column.new(key: "pax", label: "Pax", export_label: "Pax", pdf_label: "Pax", type: :text, pdf_width: 38, excel_width: 10),
      Column.new(key: "room_status", label: "Room status", export_label: "Room Status", pdf_label: "Room Status", type: :text, pdf_width: 75, excel_width: 24),
      Column.new(key: "assigned_to", label: "Assigned to", export_label: "Assigned To", pdf_label: "Assigned To", type: :text, pdf_width: 80, excel_width: 24),
      Column.new(key: "booking_status", label: "Booking status", export_label: "Booking Status", pdf_label: "Booking Status", type: :text, pdf_width: 85, excel_width: 18),
      Column.new(key: "arrival", label: "Arrival", export_label: "Arrival", pdf_label: "Arrival", type: :text, pdf_width: 75, excel_width: 22),
      Column.new(key: "departure", label: "Departure", export_label: "Departure", pdf_label: "Departure", type: :text, pdf_width: 75, excel_width: 22),
      Column.new(key: "nights", label: "Nights", export_label: "Nights", pdf_label: "Nights", type: :integer, pdf_width: 42, excel_width: 10),
      Column.new(key: "remarks", label: "Remarks", export_label: "Remarks", pdf_label: "Remarks", type: :text, pdf_width: 140, excel_width: 36)
    ].freeze
    KEYS = ALL.map(&:key).freeze
    BY_KEY = ALL.index_by(&:key).freeze

    module_function

    def normalize(keys)
      wanted = Array(keys).map(&:to_s)
      KEYS.select { |key| wanted.include?(key) }
    end

    def selected(keys)
      normalize(keys).map { |key| BY_KEY.fetch(key) }
    end
  end
end
