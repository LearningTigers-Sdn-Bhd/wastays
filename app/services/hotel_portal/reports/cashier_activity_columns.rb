# frozen_string_literal: true

module HotelPortal
  module Reports
    module CashierActivityColumns
      Column = Data.define(:key, :label, :export_labels, :pdf_label, :pdf_width, :excel_width)

      ALL = [
        Column.new(key: "date_time", label: "Date and time", export_labels: [ "Date & Time" ], pdf_label: "Date & Time", pdf_width: 72, excel_width: 22),
        Column.new(key: "date", label: "Date", export_labels: [ "Date" ], pdf_label: "Date", pdf_width: 62, excel_width: 14),
        Column.new(key: "time", label: "Time", export_labels: [ "Time" ], pdf_label: "Time", pdf_width: 44, excel_width: 10),
        Column.new(key: "reservation", label: "Booking", export_labels: [ "Booking No.", "Confirmation Code" ], pdf_label: "Booking", pdf_width: 82, excel_width: 20),
        Column.new(key: "booking_number", label: "Booking number", export_labels: [ "Booking No." ], pdf_label: "Booking No.", pdf_width: 70, excel_width: 18),
        Column.new(key: "confirmation_code", label: "Confirmation number", export_labels: [ "Confirmation Code" ], pdf_label: "Confirmation", pdf_width: 78, excel_width: 20),
        Column.new(key: "guest_details", label: "Guest and room", export_labels: [ "Guest", "Room" ], pdf_label: "Guest / Room", pdf_width: 100, excel_width: 28),
        Column.new(key: "folio", label: "Folio", export_labels: [ "Folio" ], pdf_label: "Folio", pdf_width: 70, excel_width: 18),
        Column.new(key: "invoice", label: "Invoice", export_labels: [ "Invoice" ], pdf_label: "Invoice", pdf_width: 70, excel_width: 18),
        Column.new(key: "handling", label: "Handling", export_labels: [ "Handling" ], pdf_label: "Handling", pdf_width: 62, excel_width: 18),
        Column.new(key: "payment_mode", label: "Payment mode", export_labels: [ "Payment Mode" ], pdf_label: "Payment Mode", pdf_width: 86, excel_width: 24),
        Column.new(key: "stage", label: "Stage", export_labels: [ "Stage" ], pdf_label: "Stage", pdf_width: 60, excel_width: 16),
        Column.new(key: "received_by", label: "Received by", export_labels: [ "Received By" ], pdf_label: "Received By", pdf_width: 78, excel_width: 22),
        Column.new(key: "remarks", label: "Remarks", export_labels: [ "Remarks" ], pdf_label: "Remarks", pdf_width: 100, excel_width: 30),
        Column.new(key: "currency", label: "Currency", export_labels: [ "Currency" ], pdf_label: "Currency", pdf_width: 48, excel_width: 12),
        Column.new(key: "amount", label: "Amount", export_labels: [ "Amount" ], pdf_label: "Amount", pdf_width: 68, excel_width: 16)
      ].freeze
      KEYS = ALL.map(&:key).freeze
      DEFAULT_KEYS = %w[date_time booking_number guest_details handling payment_mode stage received_by currency amount].freeze
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
end
