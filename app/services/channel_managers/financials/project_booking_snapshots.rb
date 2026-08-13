# frozen_string_literal: true

module ChannelManagers
  module Financials
    class ProjectBookingSnapshots
      def self.call!(snapshot:)
        new(snapshot).call!
      end

      def initialize(snapshot)
        @snapshot = snapshot
      end

      def call!
        @snapshot.ota_financial_components.includes(:transaction_code, :booking_room).group_by(&:booking).each do |booking, components|
          project_rooms(components)
          project_taxes(booking, components.select { |component| component.component_kind == "tax" })
        end
        @snapshot
      end

      private

      def project_rooms(components)
        components.select { |component| component.component_kind == "accommodation" }.group_by(&:booking_room).each do |room, rows|
          nightly = rows.sort_by(&:stay_date).to_h do |component|
            [ component.stay_date.iso8601, {
              "date" => component.stay_date.iso8601,
              "price" => decimal(component.amount), "posting_price" => decimal(component.posting_amount),
              "currency" => component.currency, "source" => "ota_supplied",
              "original_amount" => decimal(component.original_amount), "original_currency" => component.original_currency,
              "exchange_rate" => decimal(@snapshot.exchange_rate), "exchange_rate_source" => @snapshot.exchange_rate_source,
              "ota_component_stable_key" => component.stable_key
            } ]
          end
          posted_dates = posted_stay_dates(rows.first.booking)
          nightly.merge!(room.nightly_rate_snapshot.to_h.slice(*posted_dates))
          subtotal = nightly.values.sum(0.to_d) do |value|
            value.respond_to?(:to_h) ? value.to_h["price"].to_d : value.to_d
          end
          room.update!(subtotal: subtotal, nightly_rate_snapshot: nightly)
        end
      end

      def project_taxes(booking, taxes)
        snapshot = taxes.group_by(&:stay_date).transform_keys(&:iso8601).transform_values do |rows|
          rows.sort_by(&:stable_key).map { |component| tax_posting(component) }
        end
        merge_locally_managed_tourism_tax!(snapshot, booking, taxes)
        snapshot.merge!(booking.tax_posting_snapshot.to_h.slice(*posted_stay_dates(booking)))
        booking.update_columns(
          tax_posting_snapshot: snapshot,
          tax_lines: summarize_tax_snapshot(snapshot),
          updated_at: Time.current
        )
      end

      def merge_locally_managed_tourism_tax!(snapshot, booking, ota_taxes)
        return if ota_taxes.any? { |component| ota_tourism_tax?(component) }

        local_snapshot = Bookings::BuildFinancialSnapshot.new(
          hotel: booking.hotel,
          booking: booking,
          check_in: booking.check_in,
          check_out: booking.check_out,
          guest_country: booking.guest_country,
          room_items: booking.booking_rooms.map do |room|
            { quantity: room.quantity.to_i.positive? ? room.quantity : 1, nightly_rate_snapshot: room.nightly_rate_snapshot }
          end
        ).call.tax_posting_snapshot

        local_snapshot.each do |date, postings|
          tourism_tax = Array(postings).select { |posting| posting["transaction_code_system_key"] == "tourism_tax" }
          snapshot[date] = Array(snapshot[date]) + tourism_tax if tourism_tax.any?
        end
      end

      def ota_tourism_tax?(component)
        return true if component.transaction_code.system_key == "tourism_tax"

        names = [ component.provider_name, component.provider_type ].compact.map do |value|
          value.downcase.gsub(/[^a-z0-9]+/, " ").strip
        end
        (names & [ "tourism tax", "tourist tax", "ttx", "malaysia tourism tax" ]).any?
      end

      def summarize_tax_snapshot(snapshot)
        snapshot.values.flatten.group_by do |row|
          [ row["name"], row["type"], row["is_inclusive"], row["currency"], row["source"], row["transaction_code_id"] ]
        end.map do |(name, type, inclusive, currency, source, transaction_code_id), rows|
          first = rows.first
          {
            "name" => name, "type" => type.presence || "ota_tax", "is_inclusive" => inclusive,
            "amount" => decimal(rows.sum(0.to_d) { |row| row["amount"].to_d }),
            "currency" => currency, "source" => source.presence || "ota_supplied",
            "transaction_code_id" => transaction_code_id,
            "transaction_code_system_key" => first["transaction_code_system_key"],
            "transaction_code_code" => first["transaction_code_code"]
          }.compact
        end
      end

      def posted_stay_dates(booking)
        @posted_stay_dates ||= {}
        @posted_stay_dates[booking.id] ||= FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: booking.id }, voided_by_transaction_id: nil)
          .where("folio_transactions.metadata->>'nightly_charge_key' IS NOT NULL")
          .distinct.pluck(Arel.sql("COALESCE(folio_transactions.metadata->>'stay_date', folio_transactions.posting_date::text)"))
      end

      def tax_posting(component)
        code = component.transaction_code
        {
          "posting_identity" => component.stable_key,
          "ota_financial_component_id" => component.id,
          "name" => component.provider_name, "type" => component.provider_type.presence || "ota_tax",
          "is_inclusive" => component.is_inclusive, "rate_type" => component.rate_type,
          "rate" => decimal_or_nil(component.rate), "basis" => component.basis,
          "basis_amount" => decimal_or_nil(component.basis_amount),
          "original_amount" => decimal(component.original_amount), "original_currency" => component.original_currency,
          "amount" => decimal(component.amount), "currency" => component.currency,
          "transaction_code_id" => code.id, "transaction_code_system_key" => code.system_key,
          "transaction_code_code" => code.code, "source" => "ota_supplied", "stay_date" => component.stay_date.iso8601
        }.compact
      end

      def decimal(value) = value.to_d.to_s("F")

      def decimal_or_nil(value)
        decimal(value) unless value.nil?
      end
    end
  end
end
