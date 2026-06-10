# frozen_string_literal: true

require "csv"
require "cgi"

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

  def initialize(hotel:, start_date:, end_date:)
    @hotel      = hotel
    @start_date = start_date.to_date
    @end_date   = end_date.to_date
  end

  def generate_csv
    CSV.generate(headers: true) do |csv|
      csv << CSV_HEADERS
      each_row { |row| csv << row }
    end
  end

  def generate_xls
    rows_xml = [ spreadsheet_row(CSV_HEADERS) ]
    each_row { |row| rows_xml << spreadsheet_row(row) }

    <<~XML
      <?xml version="1.0"?>
      <?mso-application progid="Excel.Sheet"?>
      <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
        xmlns:o="urn:schemas-microsoft-com:office:office"
        xmlns:x="urn:schemas-microsoft-com:office:excel"
        xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="Folio Ledger">
          <Table>
            #{rows_xml.join("\n")}
          </Table>
        </Worksheet>
        <Worksheet ss:Name="Summary">
          <Table>
            #{summary_rows_xml}
          </Table>
        </Worksheet>
      </Workbook>
    XML
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

  def each_row(&block)
    transactions.each do |txn|
      folio   = txn.booking_folio
      booking = folio.booking

      room_number = booking.booking_rooms.first&.room_number.to_s
      tax_type    = txn.metadata["tax_line"]&.dig("type").to_s.presence ||
                    (txn.category == "tax" ? derive_tax_type(txn) : "")

      row = [
        txn.posting_date.iso8601,
        booking.formatted_invoice_number.to_s,
        booking.formatted_folio_number.to_s,
        booking.confirmation_token,
        booking.guest_name,
        room_number,
        txn.transaction_type,
        txn.category,
        gl_code_for(txn, tax_type),
        txn.description.to_s,
        txn.amount.to_f.round(2),
        txn.currency.presence || booking.currency.presence || "MYR",
        tax_type,
        txn.metadata["posting_source"].to_s,
        txn.metadata["night_audit_id"].to_s,
        txn.posted_at&.iso8601.to_s
      ]

      block.call(row)
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

  # ──────────────────────────────────────────────
  # XLS helpers
  # ──────────────────────────────────────────────

  def summary_rows_xml
    t = totals
    rows = [
      spreadsheet_row([ "Period", "#{@start_date.iso8601} to #{@end_date.iso8601}" ]),
      spreadsheet_row([ "Room Revenue",      format_money(t[:room_revenue]) ]),
      spreadsheet_row([ "Tax Revenue",       format_money(t[:tax_revenue]) ]),
      spreadsheet_row([ "Other Charges",     format_money(t[:other_charges]) ]),
      spreadsheet_row([ "Total Payments",    format_money(t[:total_payments]) ]),
      spreadsheet_row([ "Total Refunds",     format_money(t[:total_refunds]) ]),
      spreadsheet_row([ "Total Adjustments", format_money(t[:total_adjustments]) ])
    ]
    rows.join("\n")
  end

  def spreadsheet_row(values)
    cells = values.map do |value|
      escaped = CGI.escapeHTML(value.to_s)
      %(<Cell><Data ss:Type="String">#{escaped}</Data></Cell>)
    end.join
    %(<Row>#{cells}</Row>)
  end

  def format_money(value)
    format("%.2f", value.to_d)
  end
end
