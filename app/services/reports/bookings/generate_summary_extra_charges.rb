# frozen_string_literal: true

module Reports
  module Bookings
    class GenerateSummaryExtraCharges
      def initialize(hotel:, bookings:, group: false)
        @hotel = hotel
        @bookings = bookings.index_by(&:id)
        @group = group
      end

      def call
        self
      end

      def charge_rows
        @charge_rows ||= posted_charges.map { |charge| transaction_row(charge) } + forecasts.map { |forecast| forecast_row(forecast) }
      end

      def base_total = charge_rows.sum(0.to_d) { |row| row.net.to_d }

      def tax_total = charge_rows.sum(0.to_d) { |row| row.charges.to_d }

      def total = base_total + tax_total

      private

      def folio_scope
        { hotel_id: @hotel.id, booking_id: @bookings.keys }
      end

      def transactions
        @transactions ||= FolioTransaction.joins(:booking_folio)
          .where(booking_folios: folio_scope)
          .charges
          .includes(:booking_folio, :transaction_code)
          .order(:posting_date, :id).to_a
      end

      def posted_charges
        @posted_charges ||= begin
          extra_ids = transactions.select { |transaction| transaction.metadata.to_h["extra_charge_id"].present? }.map(&:id)
          transactions.select do |transaction|
            metadata = transaction.metadata.to_h
            extra = metadata["extra_charge_id"].present? ||
              extra_ids.include?(transaction.parent_transaction_id) ||
              extra_ids.include?(metadata["parent_folio_transaction_id"].to_i) ||
              extra_ids.include?(metadata["parent_transaction_id"].to_i)
            extra && transaction.voided_by_transaction_id.blank? && transaction.reversal_of_transaction_id.blank? && !tourism_tax?(metadata)
          end
        end
      end

      def forecasts
        @forecasts ||= FolioForecastedCharge.joins(:booking_folio)
          .where(booking_folios: folio_scope)
          .scheduled_extra_charges.forecast
          .includes(:booking_folio)
          .order(:stay_date, :id).reject do |forecast|
            tourism_tax?(forecast.metadata.to_h) || posted_forecast?(forecast)
          end
      end

      def posted_forecast?(forecast)
        posted_charges.any? do |transaction|
          metadata = transaction.metadata.to_h
          metadata["forecast_id"].to_i == forecast.id ||
            transaction.id == forecast.actualizing_transaction_id ||
            (metadata["forecast_identity"] == forecast.identity &&
              metadata["charge_kind"] == forecast.charge_kind &&
              metadata["stay_date"].to_s == forecast.stay_date.iso8601)
        end
      end

      def tourism_tax?(metadata)
        Booking.tourism_tax_line?(metadata) || Booking.tourism_tax_line?(metadata["tax_line"]) ||
          Booking.tourism_tax_line?(primary_tax_key: metadata["tax_rule_key"].to_s.delete_prefix("primary:"))
      end

      def transaction_row(transaction)
        metadata = transaction.metadata.to_h
        row(
          folio: transaction.booking_folio,
          date: metadata["stay_date"].presence || transaction.posting_date,
          code: transaction.posted_transaction_code,
          description: transaction.description,
          quantity: metadata["extra_charge_quantity"].presence || metadata["quantity"],
          amount: transaction.amount.to_d,
          tax: transaction.category == "tax"
        )
      end

      def forecast_row(forecast)
        metadata = forecast.metadata.to_h
        row(
          folio: forecast.booking_folio,
          date: forecast.stay_date,
          code: metadata["transaction_code_code"],
          description: forecast.description,
          quantity: metadata["quantity"],
          amount: forecast.amount.to_d,
          tax: forecast.charge_kind == "extra_charge_tax"
        )
      end

      def row(folio:, date:, code:, description:, quantity:, amount:, tax:)
        GenerateReservationRecords::ChargeRow.new(
          date: GenerateReservationRecords::PdfTheme.format_date(date.to_date),
          code: code.presence || (tax ? "TAX" : "EXTRA"),
          description:,
          secondary_description: @group ? @bookings.fetch(folio.booking_id).confirmation_token : nil,
          quantity: tax ? "-" : quantity.presence&.to_s || "1",
          net: tax ? nil : amount,
          charges: tax ? amount : nil,
          gross: amount
        )
      end
    end
  end
end
