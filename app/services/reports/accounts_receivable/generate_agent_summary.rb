# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module AccountsReceivable
    class GenerateAgentSummary
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        pdf = Prawn::Document.new(
          page_size: "A4",
          margin: [ 32, 32, 32, 32 ],
          info: {
            Title: "Agent Summary Statement - #{@hotel.name}",
            Author: "WAStays",
            Creator: "WAStays",
            CreationDate: Time.current
          }
        )

        draw_header(pdf)
        draw_totals(pdf)
        draw_table(pdf)

        pdf.render
      end

      private

      def draw_header(pdf)
        pdf.text "Agent Summary Statement", size: 18, style: :bold
        pdf.move_down 4
        pdf.text @hotel.name.to_s, size: 11, style: :bold
        pdf.text "As of #{@report.as_of_date.strftime('%d %b %Y')}", size: 10
        pdf.move_down 12
      end

      def draw_totals(pdf)
        return if @report.totals.empty?

        rows = @report.totals.map do |currency, bucket_totals|
          [
            currency,
            money(bucket_totals.current),
            money(bucket_totals.days_1_30),
            money(bucket_totals.days_31_60),
            money(bucket_totals.days_61_90),
            money(bucket_totals.days_over_90),
            money(bucket_totals.total)
          ]
        end

        pdf.table([
          [ "Currency", "Current", "1-30", "31-60", "61-90", "90+", "Total" ]
        ] + rows, width: pdf.bounds.width, cell_style: { size: 9, padding: [ 6, 6, 6, 6 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
        pdf.move_down 16
      end

      def draw_table(pdf)
        pdf.text "Agent & Airline Accounts", size: 12, style: :bold
        pdf.move_down 6

        if @report.rows.empty?
          pdf.text "No outstanding balances for agent or airline accounts.", size: 10, style: :italic
          return
        end

        rows = @report.rows.map do |row|
          [
            row.corporate_account.name,
            row.currency,
            money(row.buckets.current),
            money(row.buckets.days_1_30),
            money(row.buckets.days_31_60),
            money(row.buckets.days_61_90),
            money(row.buckets.days_over_90),
            money(row.total_outstanding)
          ]
        end

        pdf.table([
          [ "Account", "Currency", "Current", "1-30", "31-60", "61-90", "90+", "Total" ]
        ] + rows, width: pdf.bounds.width, cell_style: { size: 8, padding: [ 5, 5, 5, 5 ] }) do
          row(0).font_style = :bold
          row(0).background_color = "F1F5F9"
        end
      end

      def money(value)
        ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", value.to_d))
      end
    end
  end
end
