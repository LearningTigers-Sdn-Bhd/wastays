# frozen_string_literal: true

module Folios
  module Charges
    module NightlyChargeCalculation
      extend ActiveSupport::Concern

      private


      def ota_financial_snapshot_for(booking)
        OtaFinancialSnapshot.current
          .where("booking_id = :booking_id OR group_booking_id = :group_booking_id", booking_id: booking.id, group_booking_id: booking.group_booking_id)
          .order(created_at: :desc, id: :desc)
          .first
      end

      def ota_financial_components_for(booking, business_date = nil)
        snapshot = ota_financial_snapshot_for(booking)
        return OtaFinancialComponent.none if snapshot.blank? || snapshot.reconciliation_status == "total_mismatch"

        components = snapshot.ota_financial_components.where(booking_id: booking.id)
        components = components.where(stay_date: business_date.to_date) if business_date.present?
        posted = posted_ota_component_identities(booking)
        components.order(:stay_date, :stable_key, :id).reject do |component|
          posted.include?([ component.stable_key, component.stay_date, ota_charge_kind(component.component_kind) ])
        end
      end

      def ota_financial_component_lines(booking, business_date = nil)
        ota_financial_components_for(booking, business_date).filter_map do |component|
          amount = component.posting_amount.to_d
          next if amount.zero?

          {
            stay_date: component.stay_date,
            charge_kind: ota_charge_kind(component.component_kind),
            category: component.component_kind == "discount" ? "discount" : component.transaction_code.category,
            transaction_type: component.component_kind == "discount" ? "adjustment" : "charge",
            identity: component.stable_key,
            amount: amount,
            description: "OTA #{component.component_kind.humanize}: #{component.provider_name} - #{component.stay_date}",
            transaction_code: component.transaction_code,
            transaction_code_id: component.transaction_code_id,
            metadata: {
              ota_financial_snapshot_id: component.ota_financial_snapshot_id,
              ota_financial_component_id: component.id,
              ota_component_stable_key: component.stable_key,
              ota_component_kind: component.component_kind,
              category: component.component_kind == "discount" ? "discount" : component.transaction_code.category,
              transaction_type: component.component_kind == "discount" ? "adjustment" : "charge",
              transaction_code_id: component.transaction_code_id,
              transaction_code_system_key: component.transaction_code.system_key,
              transaction_code_code: component.transaction_code.code,
              provider_name: component.provider_name,
              provider_type: component.provider_type,
              original_amount: component.original_amount.to_s("F"),
              original_currency: component.original_currency,
              converted_amount: component.amount.to_s("F"),
              posting_amount: component.posting_amount.to_s("F"),
              currency: component.currency,
              gross_effect_amount: component.gross_effect_amount.to_s("F"),
              is_inclusive: component.is_inclusive,
              mapping_status: component.mapping_status
            }.compact
          }
        end
      end

      def posted_ota_component_identities(booking)
        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: booking.id }, voided_by_transaction_id: nil)
          .where("folio_transactions.metadata->>'ota_component_stable_key' IS NOT NULL")
          .pluck(
            Arel.sql("folio_transactions.metadata->>'ota_component_stable_key'"),
            Arel.sql("COALESCE(folio_transactions.metadata->>'stay_date', folio_transactions.posting_date::text)"),
            Arel.sql("folio_transactions.metadata->>'charge_kind'")
          ).map { |stable_key, stay_date, charge_kind| [ stable_key, stay_date.to_date, charge_kind ] }.to_set
      end

      def ota_financial_snapshot_available?(booking)
        ota_financial_snapshot_for(booking).present?
      end

      def ota_charge_kind(component_kind)
        { "fee" => "ota_fee", "service" => "ota_service", "discount" => "ota_discount" }.fetch(component_kind, component_kind)
      end

      def nightly_amount(total_amount, booking, business_date)
        stay_dates = booking_stay_dates(booking)
        nights = stay_dates.length
        return 0.to_d unless nights.positive?

        per_night = (total_amount.to_d / nights).round(2)
        return per_night unless business_date.to_date == stay_dates.last

        total_amount.to_d - (per_night * (nights - 1))
      end

      def booking_stay_dates(booking)
        Bookings::ScheduledStay.stay_dates(
          hotel: booking.hotel,
          check_in: booking.check_in,
          check_out: booking.check_out
        )
      end

      def tax_lines_for(booking)
        tax_lines = Array(booking.tax_lines)
        return tax_lines if tax_lines.any?

        return [] unless booking.tourism_tax_amount.to_d.positive?

        [ { "name" => "Tourism Tax", "amount" => booking.tourism_tax_amount, "type" => "tourism_tax" } ]
      end

      def nightly_room_amount(booking_room, business_date)
        snapshot = nightly_rate_snapshot_for(booking_room, business_date)
        return (snapshot["posting_price"].presence || snapshot["price"]).to_d if snapshot.present?

        nightly_amount(booking_room.subtotal, booking_room.booking, business_date)
      end

      def nightly_rate_snapshot_for(booking_room, business_date)
        booking_room.nightly_rate_snapshot.to_h[business_date.to_date.iso8601]
      end

      def tax_postings_for(booking, business_date)
        postings = booking.tax_posting_snapshot.to_h[business_date.to_date.iso8601]
        return postings if postings.present?

        tax_lines_for(booking).each_with_index.map do |tax_line, index|
          tax_line.to_h.merge(
            "amount" => nightly_amount(tax_line_amount(tax_line), booking, business_date).to_s("F"),
            "tax_line_index" => index,
            "source" => tax_line["source"].presence || tax_line[:source].presence || "legacy_tax_lines"
          )
        end
      end

      def tax_line_amount(tax_line)
        (tax_line["amount"].presence || tax_line[:amount]).to_d
      end

      def tax_line_name(tax_line)
        tax_line["name"].presence || tax_line[:name].presence || "Tax"
      end

      def tax_line_identity(tax_line, index)
        identity = tax_line["posting_identity"].presence || tax_line[:posting_identity].presence ||
          tax_line["type"].presence || tax_line[:type].presence || tax_line_name(tax_line).parameterize.presence || "tax"
        "#{identity}:#{index}"
      end
    end
  end
end
