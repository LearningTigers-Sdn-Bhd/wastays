# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    class DailyRevenuePdfExportService
      def initialize(hotel:, report:, transactions: [])
        @hotel = hotel
        @report = report
        @transactions = transactions
      end

      def generate
        pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])

        draw_header(pdf)
        draw_summary(pdf)
        draw_daily_table(pdf)
        pdf.move_down 12
        draw_source_table(pdf)
        draw_transactions_table(pdf) if @transactions.present?

        pdf.render
      end

      private

      def draw_header(pdf)
        logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
        if File.exist?(logo_path)
          pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
        end

        pdf.text "Daily Revenue Report", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold

        period = if @report.start_date == @report.end_date
          @report.start_date.strftime("%d %b %Y")
        else
          "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
        end

        pdf.text period, size: 10
        pdf.move_down 12
      end

      def draw_summary(pdf)
        cards = [
          [ "Bookings", @report.totals[:booking_count].to_s ],
          [ "Total Charges", money(@report.totals[:total_charges]) ],
          [ "Total Payments", money(@report.totals[:total_payments]) ],
          [ "Net Amount", money(@report.totals[:net_amount]) ]
        ]

        card_gap = 10
        card_height = 62
        cards_per_row = 4
        card_width = (pdf.bounds.width - (card_gap * (cards_per_row - 1))) / cards_per_row.to_f
        top = pdf.cursor

        cards.each_with_index do |(label, value), index|
          row = index / cards_per_row
          col = index % cards_per_row
          x = col * (card_width + card_gap)
          y = top - (row * (card_height + card_gap))

          pdf.bounding_box([ x, y ], width: card_width, height: card_height) do
            pdf.stroke_color "D1D5DB"
            pdf.fill_color "FFFFFF"
            pdf.fill_and_stroke_rounded_rectangle([ 0, card_height ], card_width, card_height, 8)
            pdf.fill_color "000000"
            pdf.stroke_color "000000"

            pdf.bounding_box([ 10, card_height - 10 ], width: card_width - 20, height: card_height - 20) do
              pdf.text label, size: 8, style: :bold
              pdf.move_down 8
              pdf.text value, size: 12, style: :bold
            end
          end
        end

        total_rows = (cards.size / cards_per_row.to_f).ceil
        used_height = (total_rows * card_height) + ((total_rows - 1) * card_gap)
        pdf.move_cursor_to(top - (used_height + 10))
      end

      def draw_daily_table(pdf)
        pdf.text "Daily Breakdown", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No daily revenue data for this selected period.", size: 10, style: :italic
          return
        end

        rows = @report.rows.map do |row|
          [
            row[:date].strftime("%d %b"),
            row[:booking_count].to_s,
            money(row[:accommodation]),
            money(row[:other_charges]),
            money(row[:tax]),
            money(row[:total_charges]),
            money(row[:discount]),
            money(row[:gateway_payment]),
            money(row[:cash_payment]),
            money(row[:booking_payment]),
            money(row[:refund]),
            money(row[:net_amount])
          ]
        end

        pdf.table([
          [ "Date", "Bkgs", "Accom", "Other", "Tax", "Charges", "Disc", "Online", "Cash", "Deposit", "Refund", "Net" ]
        ] + rows, width: pdf.bounds.width, cell_style: { size: 7, padding: [ 4, 4, 4, 4 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def draw_source_table(pdf)
        pdf.text "Revenue by Source", size: 12, style: :bold
        pdf.move_down 6

        if @report.source_rows.empty?
          pdf.text "No source revenue data for this selected period.", size: 10, style: :italic
          return
        end

        rows = @report.source_rows.map do |row|
          [
            row[:source],
            row[:booking_count].to_s,
            money(row[:accommodation]),
            money(row[:other_charges]),
            money(row[:tax]),
            money(row[:total_charges]),
            money(row[:net_amount])
          ]
        end

        pdf.table([
          [ "Source", "Bookings", "Accommodation", "Other Charges", "Tax", "Total Charges", "Net" ]
        ] + rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def draw_transactions_table(pdf)
        pdf.start_new_page(layout: :landscape)
        pdf.text "All Transactions", size: 12, style: :bold
        pdf.move_down 6

        rows = @transactions.map do |transaction|
          row = HotelPortal::Reports::DailyRevenueTransactionRow.new(transaction)
          [
            "#{row.posting_date.strftime('%d %b')} #{row.posted_at&.strftime('%H:%M')}",
            "#{row.transaction_code} / #{row.service_name}",
            "#{row.transaction_type.to_s.humanize} / #{row.category.to_s.humanize}",
            "#{row.booking_reference} / #{row.folio_number}",
            "#{row.guest_name} / #{row.room_number}",
            row.description.to_s,
            "#{row.currency} #{money(row.signed_amount)}",
            row.relationship_status
          ]
        end

        pdf.table([
          [ "Date/Time", "Code/Service", "Type/Category", "Booking/Folio", "Guest/Room", "Description", "Amount", "Status" ]
        ] + rows, width: pdf.bounds.width, cell_style: { size: 7, padding: [ 4, 4, 4, 4 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def money(value)
        format("%.2f", value.to_d)
      end
    end
  end
end
