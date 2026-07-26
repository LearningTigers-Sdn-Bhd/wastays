# frozen_string_literal: true

module Folios
  module Charges
    class ProcessCatchUpCharges
      include NightlyChargeCalculation

      def self.call(booking:, user:, is_reinstate: false, posting_date: nil, reason: nil)
        new(booking: booking, user: user, is_reinstate: is_reinstate, posting_date: posting_date, reason: reason).call
      end

      def initialize(booking:, user:, is_reinstate: false, posting_date: nil, reason: nil)
        @booking = booking
        @folio = booking.booking_folio
        @user = user
        @hotel = booking.hotel
        @is_reinstate = is_reinstate
        @reason = reason.to_s.presence
      end

      def call
        return unless @folio

        @booking.with_lock do
          reverse_no_show_charges
          post_missing_nightly_charges

          Folios::Forecasts::SyncForecastedCharges.call(booking_folio: @folio)
        end
      end

      private

      def reverse_no_show_charges
        @folio.folio_transactions.charge
          .where(category: %w[no_show_charge tax])
          .where("metadata->>'posting_source' = ?", "no_show")
          .find_each do |charge_record|
          next if already_corrected?(charge_record)

          description = @is_reinstate ? "Void Charge: Reinstated Reservation" : "Auto-reversal of no-show charge: #{charge_record.description}"

          result = Folios::Transactions::InsertTransaction.new(
            booking_folio: @folio,
            amount: -charge_record.amount,
            transaction_type: :adjustment,
            category: :correction,
            user: @user,
            description: description,
            posting_date: charge_record.posting_date,
            options: {
              override_night_audit: true,
              correction_reason: "late_checkin_correction",
              correction_note: description,
              metadata: {
                source: "late_checkin_correction",
                reversed_transaction_id: charge_record.id,
                is_reinstate: @is_reinstate
              }
            }
          ).call

          raise "Failed to reverse no-show charge: #{result.error}" unless result.success?
        end
      end

      def post_missing_nightly_charges
        # We need to check every date from booking.check_in up to (but not including) the current open business date.
        # Charges are posted for dates that are already closed by Night Audit.
        dates_to_check.each do |date|
          post_accommodation_catch_up(date)
          post_tax_catch_up(date)
        end
      end

      def dates_to_check
        final_stay_date = @booking.check_out.to_date - 1.day
        return [] if final_stay_date < @booking.check_in.to_date

        @hotel.night_audits.where(status: "completed")
          .where(business_date: @booking.check_in.to_date..final_stay_date)
          .order(:business_date)
          .pluck(:business_date)
      end

      def post_accommodation_catch_up(date)
        @booking.booking_rooms.each do |room|
          # Unique key to prevent double-posting if they check in, out, and in again (unlikely but safe)
          charge_key = ChargePostingKeys.catch_up_charge_key(
            booking: @booking,
            date: date,
            charge_kind: "accommodation",
            identity: room.id
          )
          next if already_posted?(charge_key)

          amount = nightly_room_amount(room, date)
          next if amount.zero?

          description = @is_reinstate ? "Reinstate Charge - #{date.strftime('%d %b %Y')}" : "Backdated Check-in (Room Charge) - #{date.strftime('%d %b %Y')}"

          route = resolve_route(transaction_codes.room_revenue)
          raise "Failed to resolve accommodation catch-up charge route: #{route.error}" unless route.success?

          result = Folios::Transactions::InsertTransaction.new(
            booking_folio: route.folio,
            amount: amount,
            transaction_type: :charge,
            category: :accommodation,
            user: @user,
            description: description,
            posting_date: date,
            catch_up_key: charge_key,
            options: {
              override_night_audit: true,
              correction_reason: "late_checkin_catch_up",
              correction_note: description,
              transaction_code: transaction_codes.room_revenue,
              metadata: {
                posting_source: "catch_up",
                route_source: route.route_source,
                route_metadata: route.route_metadata,
                catch_up_key: charge_key,
                stay_date: date.iso8601,
                rate_source: nightly_rate_snapshot_for(room, date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
                nightly_rate_snapshot: nightly_rate_snapshot_for(room, date),
                is_reinstate: @is_reinstate
              }.merge(reason_metadata)
            }
          ).call

          next if result.success? || already_posted?(charge_key)

          raise "Failed to post accommodation catch-up charge: #{result.error}"
        end
      end

      def post_tax_catch_up(date)
        tax_postings_for(@booking, date).each_with_index do |tax_line, index|
          tax_identity = tax_line_identity(tax_line, index)
          charge_key = ChargePostingKeys.catch_up_charge_key(
            booking: @booking,
            date: date,
            charge_kind: "tax",
            identity: tax_identity
          )
          next if already_posted?(charge_key)

          amount = tax_line_amount(tax_line)
          next if amount.zero?

          description = if @is_reinstate
            "Reinstate Tax: #{tax_line_name(tax_line)} - #{date.strftime('%d %b %Y')}"
          else
            "Backdated Check-in Tax: #{tax_line_name(tax_line)} - #{date.strftime('%d %b %Y')}"
          end

          transaction_code = transaction_codes.for_tax_line(tax_line)
          route = resolve_route(transaction_code, fallback_transaction_code: transaction_codes.source_for_tax_line(tax_line))
          raise "Failed to resolve tax catch-up charge route: #{route.error}" unless route.success?

          result = Folios::Transactions::InsertTransaction.new(
            booking_folio: route.folio,
            amount: amount,
            transaction_type: :charge,
            category: :tax,
            user: @user,
            description: description,
            posting_date: date,
            catch_up_key: charge_key,
            options: {
              override_night_audit: true,
              correction_reason: "late_checkin_catch_up",
              correction_note: description,
              transaction_code: transaction_code,
              metadata: {
                posting_source: "catch_up",
                route_source: route.route_source,
                route_metadata: route.route_metadata,
                catch_up_key: charge_key,
                stay_date: date.iso8601,
                tax_line: tax_line,
                is_reinstate: @is_reinstate
              }.merge(reason_metadata)
            }
          ).call

          next if result.success? || already_posted?(charge_key)

          raise "Failed to post tax catch-up charge: #{result.error}"
        end
      end

      def already_corrected?(charge_record)
        @folio.folio_transactions.adjustment
          .where("metadata->>'reversed_transaction_id' = ?", charge_record.id.to_s)
          .exists?
      end

      def already_posted?(charge_key)
        # Check both standard audit keys and catch-up keys to be safe
        nightly_key = charge_key.sub("catch_up:", "")
        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: @booking.id })
          .charge
          .where("catch_up_key = :charge_key OR metadata->>'catch_up_key' = :charge_key OR metadata->>'nightly_charge_key' = :nightly_key", charge_key: charge_key, nightly_key: nightly_key)
          .where(voided_by_transaction_id: nil)
          .exists?
      end

      def resolve_route(transaction_code, fallback_transaction_code: nil)
        Folios::Routing::ResolveTargetFolio.call(
          booking: @booking,
          transaction_code: transaction_code,
          fallback_transaction_code: fallback_transaction_code
        )
      end

      def transaction_codes
        @transaction_codes ||= TransactionCodes::Resolver.for(@hotel)
      end

      def reason_metadata
        return {} if @reason.blank?

        { backdate_reason: @reason }
      end
    end
  end
end
