# frozen_string_literal: true

# Exports a hotel's folio ledger for a given date range.
# Sources data from FolioTransaction records (not booking snapshots) to give
# a true accounting-ready view of charges, payments, adjustments, and taxes.
#
# Uses transaction-level General Ledger (GL) snapshots first, then hotel General Ledger (GL) mappings, so exports
# preserve historical accounting codes while supporting legacy rows.
class FolioLedgerExportService
  CSV_HEADERS = [
    "Posting Date",
    "Invoice Number",
    "Folio Number",
    "Booking Ref",
    "Guest Name",
    "Room Number",
    "Transaction Type",
    "Category",
    "General Ledger Code (GL Code)",
    "Description",
    "Amount",
    "Currency",
    "Tax Type",
    "Posting Source",
    "Night Audit ID",
    "Posted At"
  ].freeze
  PDF_HEADERS = [ "Date", "Invoice", "Folio", "Booking Ref", "Guest", "Type", "GL Code", "Description", "Amount", "Currency" ].freeze
  PDF_COLUMN_INDEXES = [ 0, 1, 2, 3, 4, 6, 8, 9, 10, 11 ].freeze
  PDF_COLUMN_WIDTHS = [ 60, 75, 70, 80, 90, 65, 60, 160, 70, 47 ].freeze

  def initialize(hotel:, start_date:, end_date:)
    @hotel      = hotel
    @start_date = start_date.to_date
    @end_date   = end_date.to_date
  end

  def generate_csv
    support = HotelPortal::Reports::Exports::CsvReportSupport.new
    support.generate do |csv|
      csv << CSV_HEADERS
      export_rows.each do |row|
        csv << row.each_with_index.map do |value, index|
          case index
          when 0 then support.date(value)
          when 10 then support.money(value)
          when 15 then support.text(value&.iso8601)
          else support.text(value)
          end
        end
      end
    end
  end

  def generate_xlsx
    HotelPortal::Reports::Exports::ExcelReportBuilder.new(
      hotel: @hotel, title: "Folio Ledger", period_label: period_label
    ).generate do |builder|
      sheet = builder.add_sheet(name: "Folio Ledger", widths: [ 14, 18, 18, 18, 22, 14, 16, 18, 20, 28, 14, 12, 14, 18, 16, 22 ], orientation: :landscape)
      builder.add_header(sheet: sheet)
      builder.add_summary(sheet: sheet, metrics: summary_metrics)
      builder.add_table(
        sheet: sheet, section_title: "Ledger Transactions", headers: CSV_HEADERS,
        rows: export_rows, column_types: %i[date text text text text text text text text text money text text text text datetime],
        total_row: nil, empty_message: "No folio transactions found for this period."
      )
    end
  end

  def generate_pdf
    builder = HotelPortal::Reports::Exports::PdfReportBuilder.new(
      hotel: @hotel, title: "Folio Ledger", period_label: period_label, page_layout: :landscape
    )
    builder.add_header
    builder.add_summary(summary_metrics.map { |label, value, currency| [ label, currency ? "#{currency} #{format_money(value)}" : value.to_s ] })
    builder.add_table(
      section_title: "Ledger Transactions", headers: PDF_HEADERS,
      rows: export_rows.map { |row| pdf_row(row) }, numeric_columns: [ 8 ], total_row: nil,
      empty_message: "No folio transactions found for this period.", column_widths: PDF_COLUMN_WIDTHS
    )
    builder.render
  end

  # Returns aggregated totals for UI display (used by reports controller).
  def totals
    @totals ||= begin
      txns = transactions.to_a
      {
        room_revenue:    txns.select { |t| t.category == "accommodation" && t.charge? }.sum(&:amount).to_d,
        tax_revenue:     txns.select { |t| t.category == "tax" && t.charge? }.sum(&:amount).to_d,
        other_charges:   txns.select { |t| t.charge? && !%w[accommodation tax].include?(t.category) }.sum(&:amount).to_d,
        total_payments:  txns.select { |t| t.payment? && t.amount.to_d.positive? }.sum(&:amount).to_d,
        total_refunds:   txns.select { |t| t.payment? && t.amount.to_d.negative? }.sum(&:amount).to_d.abs,
        total_adjustments: txns.select(&:adjustment?).sum(&:amount).to_d
      }
    end
  end

  private

  def transactions
    @transactions ||= FolioTransaction
      .joins(booking_folio: :booking)
      .where(bookings: { hotel_id: @hotel.id })
      .where(posting_date: @start_date..@end_date)
      .includes(booking_folio: { booking: :booking_rooms })
      .order(:posting_date, :id)
  end

  def gl_maps_by_category
    @gl_maps_by_category ||= @hotel.hotel_general_ledger_maps.index_by(&:transaction_category)
  end

  def export_rows
    @export_rows ||= transactions.map do |txn|
      folio   = txn.booking_folio
      booking = folio.booking

      room_number = booking.booking_rooms.first&.room_number.to_s
      tax_type    = txn.metadata["tax_line"]&.dig("type").to_s.presence ||
                    (txn.category == "tax" ? derive_tax_type(txn) : "")

      row = [
        txn.posting_date,
        booking.formatted_invoice_number.to_s,
        folio.folio_reference_display.to_s,
        booking.confirmation_token,
        booking.guest_name,
        room_number,
        txn.transaction_type,
        txn.category,
        gl_code_for(txn, tax_type),
        txn.description.to_s,
        txn.amount.to_d,
        txn.currency.presence || booking.currency.presence || "MYR",
        tax_type,
        txn.metadata["posting_source"].to_s,
        txn.metadata["night_audit_id"].to_s,
        txn.posted_at
      ]
    end
  end

  def gl_code_for(txn, _tax_type)
    txn.gl_code.presence || gl_maps_by_category[txn.category]&.gl_code.presence || "9999"
  end

  def derive_tax_type(txn)
    desc = txn.description.to_s.downcase
    return "sst"           if desc.include?("sst") || desc.include?("service tax")
    return "tourism_tax"   if desc.include?("tourism")

    "tax"
  end

  def summary_metrics
    t = totals
    currency = @hotel.default_currency.presence || "MYR"
    [
      [ "Room Revenue", t[:room_revenue], currency ], [ "Tax Revenue", t[:tax_revenue], currency ],
      [ "Other Charges", t[:other_charges], currency ], [ "Total Payments", t[:total_payments], currency ],
      [ "Total Refunds", t[:total_refunds], currency ], [ "Total Adjustments", t[:total_adjustments], currency ]
    ]
  end

  def pdf_row(row)
    PDF_COLUMN_INDEXES.map do |index|
      value = row[index]
      case index
      when 0 then value.strftime("%d %b %Y")
      when 10 then format_money(value)
      else value.presence || "-"
      end
    end
  end

  def period_label = @start_date == @end_date ? @start_date.strftime("%d %b %Y") : "#{@start_date.strftime('%d %b %Y')} - #{@end_date.strftime('%d %b %Y')}"

  def format_money(value)
    format("%.2f", value.to_d)
  end
end
