# frozen_string_literal: true

module HotelPortal
  module Reports
    BookingPerformanceColumns = ReportColumns.build(
      columns: [
        ReportColumns.column(key: "booked_on", label: "Booked on", export_labels: [ "Booked On" ], pdf_label: "Booked On", pdf_width: 60, excel_width: 14, type: :date),
        ReportColumns.column(key: "booking", label: "Booking", export_labels: [ "Booking Number", "Confirmation Code" ], pdf_label: "Booking", pdf_width: 88, excel_width: 20, type: :text),
        ReportColumns.column(key: "confirmation_code", label: "Confirmation code", export_labels: [ "Confirmation Code" ], pdf_label: "Confirmation", pdf_width: 76, excel_width: 20, type: :text),
        ReportColumns.column(key: "guest", label: "Guest", export_labels: [ "Guest Name" ], pdf_label: "Guest", pdf_width: 100, excel_width: 26, type: :text),
        ReportColumns.column(key: "stay", label: "Stay", export_labels: [ "Check In", "Check Out" ], pdf_label: "Stay", pdf_width: 76, excel_width: 14, type: :date),
        ReportColumns.column(key: "check_in", label: "Check-in", export_labels: [ "Check In" ], pdf_label: "Check In", pdf_width: 58, excel_width: 14, type: :date),
        ReportColumns.column(key: "check_out", label: "Check-out", export_labels: [ "Check Out" ], pdf_label: "Check Out", pdf_width: 58, excel_width: 14, type: :date),
        ReportColumns.column(key: "source", label: "Source", export_labels: [ "Source" ], pdf_label: "Source", pdf_width: 62, excel_width: 18, type: :text),
        ReportColumns.column(key: "fund_collector", label: "Collected by", export_labels: [ "Collected By" ], pdf_label: "Collected By", pdf_width: 68, excel_width: 18, type: :text),
        ReportColumns.column(key: "status", label: "Status", export_labels: [ "Status" ], pdf_label: "Status", pdf_width: 62, excel_width: 18, type: :text),
        ReportColumns.column(key: "payment_status", label: "Payment status", export_labels: [ "Payment Status" ], pdf_label: "Payment", pdf_width: 62, excel_width: 18, type: :text),
        ReportColumns.column(key: "gross", label: "Gross price", export_labels: [ "Gross" ], pdf_label: "Gross", pdf_width: 58, excel_width: 14, type: :money),
        ReportColumns.column(key: "taxes", label: "Taxes", export_labels: [ "Taxes" ], pdf_label: "Taxes", pdf_width: 52, excel_width: 14, type: :money),
        ReportColumns.column(key: "commission", label: "Commission", export_labels: [ "Commission" ], pdf_label: "Commission", pdf_width: 64, excel_width: 14, type: :money),
        ReportColumns.column(key: "net", label: "Net payout", export_labels: [ "Net" ], pdf_label: "Net", pdf_width: 58, excel_width: 14, type: :money),
        ReportColumns.column(key: "currency", label: "Currency", export_labels: [ "Currency" ], pdf_label: "Currency", pdf_width: 48, excel_width: 12, type: :text)
      ],
      defaults: %w[booked_on booking guest stay source fund_collector status payment_status gross taxes commission net]
    )
  end
end
