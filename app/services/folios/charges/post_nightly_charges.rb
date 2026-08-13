# frozen_string_literal: true

module Folios
  module Charges
    class PostNightlyCharges
      include NightlyChargeCalculation
      Result = Struct.new(:posted, :skipped, :failed, keyword_init: true)

      def self.call(night_audit:, user:, options: {})
        new(night_audit: night_audit, user: user, options: options).call
      end

      def initialize(night_audit:, user:, options: {})
        @night_audit = night_audit
        @hotel = night_audit.hotel
        @business_date = night_audit.business_date.to_date
        @user = user
        @options = options
        @posted = []
        @skipped = []
        @failed = []
      end

      def call
        bookings_to_post.each do |booking|
          unless booking.booking_folio
            record_skipped(item_for(booking, "booking:#{booking.id}", reason: "Booking has no folio"))
            next
          end

          begin
            booking.with_lock do
              post_expected_nightly_charges(booking)
              post_extra_charge_forecasts(booking)
            end
          rescue StandardError => e
            item = @failed.last || item_for(booking, "booking:#{booking.id}", reason: e.message)
            record_item_log("item_failed", item)
            raise
          end
        end
        Result.new(posted: @posted, skipped: @skipped, failed: @failed)
      end

      private

      def bookings_to_post
        @bookings_to_post ||= @hotel.bookings
          .includes(:booking_rooms, :booking_folio)
          .checked_in
          .occupying_night_on(@business_date, @hotel.hotel_time_zone)
      end

      def post_expected_nightly_charges(booking)
        Folios::Reads::ForecastedChargeLines.call(booking: booking, dates: [ @business_date ]).each do |line|
          insert_transaction!(
            booking: booking,
            amount: line[:amount],
            transaction_type: line[:transaction_type] || "charge",
            category: line[:category],
            description: line[:description],
            transaction_code: line[:transaction_code],
            fallback_transaction_code: line[:fallback_transaction_code],
            metadata: nightly_metadata(booking, line[:charge_kind], line[:identity]).merge(line[:metadata].to_h).merge(
              tax_line: line[:tax_line]
            ).compact
          )
        end
      end

      def post_accommodation_charges(booking)
        booking.booking_rooms.each do |booking_room|
          amount = nightly_room_amount(booking_room, @business_date)
          if amount.zero?
            record_skipped(item_for(booking, "accommodation:#{booking_room.id}", category: "accommodation", reason: "Nightly room charge amount is zero"))
            next
          end

          insert_transaction!(
            booking: booking,
            amount: amount,
            category: "accommodation",
            description: "Room Charge - #{@business_date}",
            transaction_code: transaction_codes.room_revenue,
            fallback_transaction_code: nil,
            metadata: nightly_metadata(booking, "accommodation", booking_room.id).merge(
              rate_source: nightly_rate_snapshot_for(booking_room, @business_date).present? ? "nightly_rate_snapshot" : "legacy_subtotal_average",
              nightly_rate_snapshot: nightly_rate_snapshot_for(booking_room, @business_date)
            )
          )
        end
      end

      def post_tax_charges(booking)
        tax_postings_for(booking, @business_date).each_with_index do |tax_line, index|
          amount = tax_line_amount(tax_line)
          tax_identity = tax_line_identity(tax_line, index)
          if amount.zero?
            record_skipped(item_for(booking, "tax:#{tax_identity}", category: "tax", reason: "Nightly tax charge amount is zero"))
            next
          end
          insert_transaction!(
            booking: booking,
            amount: amount,
            category: "tax",
            description: "Tax: #{tax_line_name(tax_line)} - #{@business_date}",
            transaction_code: transaction_codes.for_tax_line(tax_line),
            fallback_transaction_code: transaction_codes.source_for_tax_line(tax_line),
            metadata: nightly_metadata(booking, "tax", tax_identity).merge(tax_line: tax_line)
          )
        end
      end

      def post_extra_charge_forecasts(booking)
        base_transactions = {}
        extra_charge_forecasts(booking).each do |forecast|
          metadata = forecast.metadata.to_h.symbolize_keys
          transaction_code = @hotel.transaction_codes.find_by(id: metadata[:transaction_code_id])
          unless transaction_code
            record_failed(item_for(booking, forecast.identity, category: metadata[:category], reason: "Scheduled extra charge transaction code is unavailable"))
            raise "Scheduled extra charge transaction code is unavailable"
          end

          group_key = metadata[:extra_charge_posting_key]
          parent = base_transactions[group_key]
          transaction = insert_transaction!(
            booking: booking,
            amount: forecast.amount,
            category: metadata[:category],
            description: forecast.description,
            transaction_code: transaction_code,
            fallback_transaction_code: nil,
            target_folio: forecast.booking_folio,
            parent_transaction: (parent if parent&.booking_folio_id == forecast.booking_folio_id),
            metadata: nightly_metadata(booking, forecast.charge_kind, forecast.identity).merge(
              metadata,
              forecast_id: forecast.id,
              parent_transaction_id: parent&.id
            ).compact
          )
          base_transactions[group_key] = transaction if forecast.charge_kind == "extra_charge"
        end
      end

      def extra_charge_forecasts(booking)
        FolioForecastedCharge.joins(:booking_folio)
          .includes(:booking_folio)
          .where(booking_folios: { booking_id: booking.id })
          .scheduled_extra_charges.forecast.for_date(@business_date)
          .order(Arel.sql("CASE charge_kind WHEN 'extra_charge' THEN 0 ELSE 1 END"), :id)
      end

      def insert_transaction!(booking:, amount:, category:, description:, transaction_code:, fallback_transaction_code:, metadata:, transaction_type: "charge", target_folio: nil, parent_transaction: nil)
        existing_transaction = posted_transaction(booking, metadata[:nightly_charge_key])
        if existing_transaction
          actualize_forecast!(booking, existing_transaction, metadata)
          record_skipped(item_for(booking, metadata[:nightly_charge_key], category: category, reason: "Nightly charge already posted", folio_transaction_id: existing_transaction.id))
          return existing_transaction
        end

        route = if target_folio
          Folios::Routing::RouteResult.success(folio: target_folio, route_source: "forecast_snapshot", route_metadata: {})
        else
          Folios::Routing::ResolveTargetFolio.call(
            booking: booking,
            transaction_code: transaction_code,
            fallback_transaction_code: fallback_transaction_code
          )
        end
        unless route.success?
          record_failed(item_for(booking, metadata[:nightly_charge_key], category: category, reason: route.error))
          raise "Failed to resolve nightly folio charge route: #{route.error}"
        end

        result = Folios::Transactions::InsertTransaction.new(
          booking_folio: route.folio,
          amount: amount,
          transaction_type: transaction_type,
          category: category,
          user: @user,
          description: description,
          posting_date: @business_date,
          options: @options.merge(
            posting_source: "night_audit",
            night_audit: @night_audit,
            transaction_code: transaction_code,
            parent_transaction: parent_transaction,
            metadata: metadata.merge(route_source: route.route_source, route_metadata: route.route_metadata)
          )
        ).call

        if result.success?
          actualize_forecast!(booking, result.transaction, metadata)
          @posted << item_for(booking, metadata[:nightly_charge_key], category: category, amount: result.transaction.amount.to_s, folio_transaction_id: result.transaction.id)
          return result.transaction
        end

        existing_transaction = posted_transaction(booking, metadata[:nightly_charge_key])
        if existing_transaction
          actualize_forecast!(booking, existing_transaction, metadata)
          record_skipped(item_for(booking, metadata[:nightly_charge_key], category: category, reason: "Nightly charge already posted", folio_transaction_id: existing_transaction.id))
          return existing_transaction
        end

        record_failed(item_for(booking, metadata[:nightly_charge_key], category: category, reason: result.error))
        raise "Failed to post nightly folio charge: #{result.error}"
      end

      def posted_transaction(booking, nightly_charge_key)
        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: booking.id })
          .where(voided_by_transaction_id: nil)
          .find_by(
            "metadata->>'nightly_charge_key' = :key OR metadata->>'reconciles_nightly_charge_key' = :key",
            key: nightly_charge_key
          )
      end

      def actualize_forecast!(booking, transaction, metadata)
        forecasts = FolioForecastedCharge.joins(:booking_folio)
          .where(booking_folios: { booking_id: booking.id })
          .forecast
          .where(stay_date: @business_date, charge_kind: metadata[:charge_kind], identity: metadata[:forecast_identity])

        target_forecast = forecasts.find_by(booking_folio_id: transaction.booking_folio_id)
        target_forecast&.actualize!(transaction: transaction)
        forecasts.where.not(id: target_forecast&.id).find_each(&:supersede!)
      end

      def transaction_codes
        @transaction_codes ||= TransactionCodes::Resolver.for(@hotel)
      end

      def nightly_metadata(booking, charge_kind, identity)
        {
          posting_source: "night_audit",
          night_audit_id: @night_audit.id,
          stay_date: @business_date.iso8601,
          booking_id: booking.id,
          charge_kind: charge_kind,
          forecast_identity: identity.to_s,
          nightly_charge_key: nightly_charge_key(booking, charge_kind, identity)
        }
      end

      def nightly_charge_key(booking, charge_kind, identity)
        ChargePostingKeys.nightly_charge_key(
          booking: booking,
          date: @business_date,
          charge_kind: charge_kind,
          identity: identity
        )
      end

      def item_for(booking, identity, attributes = {})
        {
          "item_key" => "nightly_charge:#{booking.id}:#{@business_date.iso8601}:#{identity}",
          "item_type" => "nightly_charge",
          "booking_id" => booking.id,
          "confirmation_token" => booking.confirmation_token
        }.merge(attributes.stringify_keys)
      end

      def record_skipped(item)
        @skipped << item
        record_item_log("item_skipped", item)
      end

      def record_failed(item)
        @failed << item
        record_item_log("item_failed", item)
      end

      def record_item_log(action_type, item)
        NightAudits::RecordLog.call!(
          night_audit: @night_audit,
          user: @user,
          action_type: action_type,
          message: item["reason"],
          metadata: { item: item }
        )
      end
    end
  end
end
