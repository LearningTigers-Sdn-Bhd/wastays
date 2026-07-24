# frozen_string_literal: true

require "ostruct"

module Folios
  class RoutePreview
    def self.call(booking:, actor: nil)
      new(booking: booking, actor: actor).call
    end

    def initialize(booking:, actor: nil)
      @booking = booking
      @actor = actor
    end

    def call
      rows = expected_lines.map { |line| row_for(line) }
      OpenStruct.new(rows: rows, grouped_by_folio: grouped_by_folio(rows))
    end

    private

    def expected_lines
      @expected_lines ||= ForecastedChargeLines.call(booking: @booking)
    end

    def row_for(line)
      transaction_code = line[:transaction_code]
      route = transaction_code.present? ? Folios::ResolveTargetFolio.call(
        booking: @booking,
        transaction_code: transaction_code,
        fallback_transaction_code: line[:fallback_transaction_code],
        actor: @actor
      ) : nil
      target_folio = route&.success? ? route.folio : nil

      {
        date: line[:stay_date],
        description: line[:description],
        amount: line[:amount].to_d,
        transaction_code: transaction_code,
        target_folio: target_folio,
        route_source: route&.route_source,
        warning: warning_for(line, route),
        display_code_label: display_code_label(line, transaction_code)
      }
    end

    def grouped_by_folio(rows)
      rows.group_by { |row| row[:target_folio] }
    end

    def warning_for(line, route)
      return "Missing transaction code" if line[:transaction_code].blank?
      return route.error if route.error.present?
      return "Missing target folio" if route.folio.blank?
      return "Target folio is closed" unless route.folio.open?

      nil
    end

    def display_code_label(line, transaction_code)
      return composite_tax_code(line, transaction_code) if line[:category].to_s == "tax" && transaction_code.present?

      transaction_code&.code.presence || fallback_code(line)
    end

    def composite_tax_code(line, transaction_code)
      source_code = source_transaction_code(line)&.code.presence
      return transaction_code.code if source_code.blank?

      "#{source_code}_#{transaction_code.code}"
    end

    def source_transaction_code(line)
      tax_line = line[:tax_line].to_h
      source_id = tax_line["source_transaction_code_id"].presence || tax_line[:source_transaction_code_id].presence
      return transaction_codes.for_id(source_id) if source_id.present?

      transaction_codes.room_revenue
    end

    def transaction_codes
      @transaction_codes ||= TransactionCodes::Resolver.for(@booking.hotel)
    end

    def fallback_code(line)
      return "ROOM" if line[:category].to_s == "accommodation"

      text = [ line[:description], line.dig(:tax_line, "type"), line.dig(:tax_line, :type) ].compact.join(" ").downcase
      return "TAX_SST" if text.include?("sst")
      return "TAX_TTX" if text.include?("tourism") || text.include?("ttx")
      return "TAX" if line[:category].to_s == "tax"

      line[:category].to_s.upcase.presence || "-"
    end
  end
end
