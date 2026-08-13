# frozen_string_literal: true

require "digest"

module ChannelManagers
  module Financials
    class PersistSnapshot
      def self.call!(financials:, booking: nil, group_booking: nil)
        new(financials:, booking:, group_booking:).call!
      end

      def initialize(financials:, booking: nil, group_booking: nil)
        @financials, @booking, @group = financials, booking, group_booking
        @bookings = booking ? [ booking ] : group_booking.bookings.includes(:booking_rooms).to_a
        @hotel = booking&.hotel || group_booking&.hotel
        @provider = @financials[:provider].presence || "channex"
        @currency = @financials[:converted_currency] || @hotel.default_currency
        @source_currency = @financials[:currency]
      end

      def call!
        target = @booking || @group
        target.lock!
        @previous_snapshot = current_target_scope.first
        identity = identity_scope.find_by(provider_revision_id: @financials[:provider_revision_id].to_s)
        if identity
          verify_identity_target!(identity)
          return identity
        end
        allocations = AllocateGroupSnapshot.call(bookings: active_bookings, rooms: @financials[:rooms])
        component_attributes = build_components(allocations)
        apply_inclusive_tax_carve_out!(component_attributes)
        accommodation = component_attributes.select { |row| row[:component_kind] == "accommodation" }.sum(0.to_d) { |row| row[:gross_effect_amount] }
        comparison = ComparePmsRate.call(bookings: active_bookings, accommodation_amount: accommodation)
        policy = EvaluateVariancePolicy.call(hotel: @hotel, variance_amount: comparison.variance_amount || 0,
          expected_amount: comparison.expected_amount || 0, room_nights: comparison.room_nights)
        gross = @financials[:converted_gross_amount].to_d
        mismatch = (gross - component_attributes.sum(0.to_d) { |row| row[:gross_effect_amount] }).round(2)
        status = reconciliation_status(component_attributes, mismatch, comparison, policy,
          source_mismatch: @financials[:source_mismatch_amount].to_d)

        OtaFinancialSnapshot.transaction(requires_new: true) do
          supersede_current!
          snapshot = OtaFinancialSnapshot.create!(
            hotel: @hotel, booking_source: booking_source, booking: @booking, group_booking: @group,
            provider: @provider, channel_manager_reference: @financials[:channel_manager_reference],
            provider_revision_id: @financials[:provider_revision_id].to_s,
            provider_revision_number: numeric_revision, original_currency: @source_currency,
            original_gross_amount: @financials[:gross_amount], currency: @currency, gross_amount: gross,
            original_accommodation_amount: original_accommodation_amount,
            accommodation_amount: accommodation, expected_pms_accommodation_amount: comparison.expected_amount,
            variance_amount: comparison.variance_amount, variance_percentage: comparison.variance_percentage,
            variance_reason: comparison.reason, exchange_rate: @financials[:exchange_rate] || 1,
            exchange_rate_source: @financials[:exchange_rate_source] || "same_currency",
            conversion_rounding_amount: @financials[:conversion_rounding_amount] || 0,
            reconciliation_status: status, mismatch_amount: mismatch, policy_snapshot: policy.snapshot,
            metadata: safe_metadata(component_attributes)
          )
          component_attributes.each { |attributes| snapshot.ota_financial_components.create!(attributes) }
          ProjectBookingSnapshots.call!(snapshot: snapshot)
          update_child_totals!(snapshot)
          snapshot
        end
      rescue ActiveRecord::RecordNotUnique
        snapshot = identity_scope.find_by!(provider_revision_id: @financials[:provider_revision_id].to_s)
        verify_identity_target!(snapshot)
        snapshot
      end

      private

      def verify_identity_target!(snapshot)
        expected_target_id = @booking&.id || @group&.id
        actual_target_id = @booking ? snapshot.booking_id : snapshot.group_booking_id
        return if actual_target_id == expected_target_id

        raise ActiveRecord::RecordNotUnique, "OTA financial revision belongs to a different target"
      end

      def active_bookings
        @bookings.reject { |item| item.status == "cancelled" }.sort_by { |item| [ item.group_position || 1, item.id ] }
      end

      def identity_scope
        OtaFinancialSnapshot.where(hotel: @hotel, provider: BookingSource.normalize(@provider),
          channel_manager_reference: @financials[:channel_manager_reference])
      end

      def current_target_scope
        @booking ? OtaFinancialSnapshot.current.where(booking: @booking) : OtaFinancialSnapshot.current.where(group_booking: @group)
      end

      def supersede_current!
        current_target_scope.update_all(current: false, superseded_at: Time.current, updated_at: Time.current)
      end

      def booking_source
        key = @financials[:booking_source_key]
        key.present? ? BookingSource.find_by(key: key) : BookingSource.find_by_source(@financials.dig(:metadata, "ota_name"))
      end

      def numeric_revision
        value = @financials[:provider_revision_id].to_s
        value.to_i if value.match?(/\A\d+\z/)
      end

      def original_accommodation_amount
        Array(@financials[:rooms]).sum(0.to_d) { |room| room[:amount].to_d }
      end

      def build_components(allocations)
        rows = []
        allocations.each do |allocation|
          room = allocation[:room]
          quantity = [ room[:quantity].to_i, 1 ].max
          days = Array(room[:days])
          days = distributed_days(room, allocation[:booking]) if days.empty?
          days.each_with_index do |day, day_index|
            original = allocate(day[:amount], quantity, allocation[:unit_index], currency: @source_currency)
            converted = allocate(day[:converted_amount], quantity, allocation[:unit_index])
            rows << component_row(allocation:, component: day.merge(kind: "accommodation"),
              original:, converted:, stay_date: day[:date], path: "rooms.#{allocation[:room_index]}.units.#{allocation[:unit_index]}.days.#{day_index}")
          end
          %i[taxes service_fees discounts].each do |collection|
            Array(room[collection]).each_with_index do |component, index|
              rows.concat(allocated_component_rows(allocation, component, quantity, collection, index))
            end
            Array(room[:days]).each_with_index do |day, day_index|
              Array(day[collection]).each_with_index do |component, index|
                rows.concat(allocated_component_rows(allocation, component, quantity, collection, index,
                  stay_date: day[:date], prefix: "days.#{day_index}."))
              end
            end
          end
        end
        append_booking_level_components!(rows, allocations)
        rows
      end

      def distributed_days(room, booking)
        dates = (booking.check_in.to_date...booking.check_out.to_date).to_a
        amounts = allocate_minor_units(room[:amount], dates.size, currency: @source_currency)
        converted = allocate_minor_units(room[:converted_amount], dates.size)
        dates.each_index.map { |index| { date: dates[index].iso8601, amount: amounts[index], converted_amount: converted[index] } }
      end

      def allocated_component_rows(allocation, component, quantity, collection, index, stay_date: nil, prefix: "")
        original = allocate(component[:amount], quantity, allocation[:unit_index], currency: @source_currency)
        converted = allocate(component[:converted_amount], quantity, allocation[:unit_index])
        component_rows_for_dates(
          allocation:, component:, original:, converted:,
          dates: component_dates(component, allocation[:booking], stay_date),
          path: "rooms.#{allocation[:room_index]}.units.#{allocation[:unit_index]}.#{prefix}#{collection}.#{index}"
        )
      end

      def append_booking_level_components!(rows, allocations)
        %i[taxes service_fees discounts].each do |collection|
          Array(@financials[collection]).each_with_index do |component, index|
            split_original = weighted_allocate(component[:amount], allocations, component, currency: @source_currency)
            split_converted = weighted_allocate(component[:converted_amount], allocations, component)
            allocations.each_with_index do |allocation, allocation_index|
              rows.concat(component_rows_for_dates(
                allocation:, component:, original: split_original[allocation_index],
                converted: split_converted[allocation_index],
                dates: component_dates(component, allocation[:booking]),
                path: "booking.#{collection}.#{index}.allocation.#{allocation_index}"
              ))
            end
          end
        end
      end

      def component_dates(component, booking, explicit_date = nil)
        return [ explicit_date.to_date ] if explicit_date.present?

        cadence = [ component.dig(:metadata, "basis"), component.dig(:metadata, "scope"),
          component.dig(:metadata, "price_mode") ].compact.join(" ").downcase
        return [ booking.check_in.to_date ] unless cadence.match?(/per.?night|room.?night|nightly|\bnight\b/)

        (booking.check_in.to_date...booking.check_out.to_date).to_a
      end

      def component_rows_for_dates(allocation:, component:, original:, converted:, dates:, path:)
        original_parts = allocate_minor_units(original, dates.size, currency: @source_currency)
        converted_parts = allocate_minor_units(converted, dates.size)
        dates.each_with_index.map do |date, index|
          component_row(
            allocation:, component:, original: original_parts[index], converted: converted_parts[index],
            stay_date: date, path: "#{path}.stay_date.#{date.iso8601}.#{index}"
          )
        end
      end

      def component_row(allocation:, component:, original:, converted:, stay_date:, path:)
        resolution = ResolveTransactionCode.call(hotel: @hotel, booking_source: booking_source,
          provider: @provider, component: component)
        kind = normalized_kind(component[:kind])
        gross_effect = if kind == "discount"
          -converted
        elsif kind == "tax" && component[:inclusive]
          0.to_d
        else
          converted
        end
        metadata = component[:metadata].to_h
        {
          booking: allocation[:booking], booking_room: kind == "accommodation" ? allocation[:booking_room] : nil,
          transaction_code: resolution.transaction_code, component_kind: kind, stable_key: path,
          stay_date:, provider_name: metadata["name"].presence || metadata["title"].presence || kind.humanize,
          provider_type: metadata["type"].presence || metadata["category"], original_currency: @source_currency,
          original_amount: original.abs, currency: @currency, amount: converted.abs,
          gross_effect_amount: gross_effect, posting_amount: kind == "discount" ? -converted : converted,
          is_inclusive: component[:inclusive] || false, rate_type: rate_type(component), rate: rate(component),
          basis: basis(component), basis_amount: basis_amount(component, allocation, stay_date), mapping_status: resolution.mapping_status,
          allocation_rounding_amount: converted - (original * (@financials[:exchange_rate] || 1).to_d).round(
            CurrencyCatalog.precision_for(@currency)
          ),
          metadata: component_metadata(metadata, allocation, kind)
        }
      end

      def component_metadata(metadata, allocation, kind)
        safe = metadata.slice(
          "code", "name", "title", "type", "category", "price_mode", "rate", "percent", "percentage",
          "basis", "scope", "applied_to", "nights", "persons", "price_per_unit"
        )
        return safe unless kind == "accommodation"

        room = allocation[:booking_room]
        safe.merge(
          "room_type_id" => room.room_type_id,
          "room_type_name" => room.room_type.name.to_s.first(255),
          "rate_plan_id" => room.rate_plan_id,
          "rate_plan_name" => room.rate_plan&.name.to_s.first(255)
        ).compact
      end

      def normalized_kind(kind)
        kind.to_s == "service_fee" ? "service" : kind.to_s
      end

      def rate_type(component)
        mode = component.dig(:metadata, "price_mode").to_s.downcase
        return "percentage" if mode.include?("percent") || provider_percentage(component)
        return "flat" unless component[:kind].to_s == "accommodation"

        nil
      end

      def rate(component)
        component.dig(:metadata, "rate") || provider_percentage(component)
      end

      def basis(component)
        component.dig(:metadata, "basis").presence || component.dig(:metadata, "scope").presence ||
          component.dig(:metadata, "price_mode").presence ||
          (rate_type(component) == "percentage" ? "nightly_room_charge" : "booking")
      end

      def basis_amount(component, allocation, stay_date)
        return component.dig(:metadata, "price_per_unit") if component.dig(:metadata, "price_per_unit").present?
        return unless rate_type(component) == "percentage"

        room = allocation[:room]
        day = Array(room[:days]).find { |item| item[:date].to_s == stay_date.to_s }
        allocate(day&.dig(:amount) || room[:amount], [ room[:quantity].to_i, 1 ].max,
          allocation[:unit_index], currency: @source_currency)
      end

      def provider_percentage(component)
        explicit = component.dig(:metadata, "percentage") || component.dig(:metadata, "percent")
        return explicit.to_d if explicit.present?

        name = component.dig(:metadata, "name").to_s
        match = name.match(/\(?([0-9]+(?:\.[0-9]+)?)%\)?/)
        match && match[1].to_d
      end

      def apply_inclusive_tax_carve_out!(rows)
        rows.select { |row| row[:component_kind] == "tax" && row[:is_inclusive] }.each do |tax|
          target_kinds = if tax.dig(:metadata, "applied_to").to_s.match?(/fee|service/) ||
              tax.dig(:metadata, "scope").to_s.match?(/fee|service/)
            %w[fee service]
          else
            [ "accommodation" ]
          end
          target = rows.reverse.find do |row|
            row[:component_kind].in?(target_kinds) && row[:booking] == tax[:booking] && row[:stay_date].to_s == tax[:stay_date].to_s
          end
          target ||= rows.reverse.find do |row|
            row[:component_kind].in?(%w[accommodation fee service]) && row[:booking] == tax[:booking] && row[:stay_date].to_s == tax[:stay_date].to_s
          end
          target[:posting_amount] -= tax[:posting_amount] if target
        end
      end

      def reconciliation_status(rows, mismatch, comparison, policy, source_mismatch:)
        return "total_mismatch" unless mismatch.zero? && source_mismatch.zero?
        return "unmapped_components" if rows.any? { |row| row[:mapping_status] == "unmapped" }
        return "rate_review_required" if posted_history? || !policy.accepted
        return "accepted_fx_variance" if comparison.variance_amount.to_d.nonzero?
        return "balanced_with_rounding" if @financials[:conversion_rounding_amount].to_d.nonzero? ||
          rows.any? { |row| row[:allocation_rounding_amount].to_d.nonzero? }
        "balanced"
      end

      def update_child_totals!(snapshot)
        active_bookings.each do |booking|
          posted_dates = posted_dates_for(booking)
          if posted_dates.any? && @previous_snapshot.blank?
            next
          elsif posted_dates.any?
            historical = @previous_snapshot.ota_financial_components
              .where(booking: booking, stay_date: posted_dates).sum(:gross_effect_amount)
            current = snapshot.ota_financial_components.where(booking: booking)
              .where.not(stay_date: posted_dates).sum(:gross_effect_amount)
            total = historical + current
          else
            total = snapshot.ota_financial_components.where(booking: booking).sum(:gross_effect_amount)
          end
          booking.update_columns(total_amount: total, updated_at: Time.current)
        end
      end

      def posted_history?
        @posted_history ||= FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: active_bookings.map(&:id) }, voided_by_transaction_id: nil)
          .where("folio_transactions.metadata->>'nightly_charge_key' IS NOT NULL")
          .exists?
      end

      def safe_metadata(component_attributes)
        metadata = @financials[:metadata].to_h.slice("ota_name", "payment_collect", "status", "tax_calculation")
          .merge("posted_history_detected" => posted_history?)
        if @financials[:source_mismatch_amount].to_d.nonzero?
          metadata["source_mismatch_amount"] = @financials[:source_mismatch_amount].to_d.to_s("F")
        end
        proposal = adjustment_proposal(component_attributes)
        proposal ? metadata.merge("adjustment_proposal" => proposal) : metadata
      end

      def adjustment_proposal(component_attributes)
        return unless posted_history?

        allocations = active_bookings.filter_map do |booking|
          dates = posted_dates_for(booking)
          desired = component_attributes.select do |row|
            row[:booking] == booking && row[:stay_date].to_date.in?(dates)
          end.sum(0.to_d) { |row| row[:posting_amount].to_d }
          actual = posted_transactions_for(booking)
            .where("folio_transactions.metadata->>'ota_component_stable_key' IS NOT NULL").sum(:amount)
          amount = desired - actual
          next if amount.zero?

          { "booking_id" => booking.id, "amount" => amount.to_s("F") }
        end
        return if allocations.empty?

        identity = Digest::SHA256.hexdigest([
          @provider, @financials[:channel_manager_reference], @financials[:provider_revision_id], allocations
        ].join(":"))
        {
          "identity" => identity,
          "status" => "pending",
          "amount" => allocations.sum(0.to_d) { |row| row["amount"].to_d }.to_s("F"),
          "currency" => @currency,
          "allocations" => allocations,
          "action" => "staff_approval_required"
        }
      end

      def posted_dates_for(booking)
        @posted_dates ||= {}
        @posted_dates[booking.id] ||= posted_transactions_for(booking).distinct.pluck(
          Arel.sql("COALESCE(folio_transactions.metadata->>'stay_date', folio_transactions.posting_date::text)")
        ).map(&:to_date)
      end

      def posted_transactions_for(booking)
        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: booking.id }, voided_by_transaction_id: nil)
          .where("folio_transactions.metadata->>'nightly_charge_key' IS NOT NULL")
      end

      def allocate(value, count, index, currency: @currency)
        allocate_minor_units(value, count, currency: currency)[index]
      end

      def allocate_minor_units(value, count, currency: @currency)
        return [] if count.zero?
        precision = CurrencyCatalog.precision_for(currency)
        unit = (value.to_d / count).round(precision)
        Array.new(count) { |index| index == count - 1 ? value.to_d - unit * (count - 1) : unit }
      end

      def weighted_allocate(value, allocations, component, currency: @currency)
        weights = allocation_weights(component, allocations)
        total = weights.sum
        weights = Array.new(weights.size, 1.to_d) if total.zero?
        total = weights.sum
        precision = CurrencyCatalog.precision_for(currency)
        allocated = weights.map { |weight| (value.to_d * weight / total).round(precision) }
        allocated[-1] += value.to_d - allocated.sum if allocated.any?
        allocated
      end

      def allocation_weights(component, allocations)
        basis = component.dig(:metadata, "basis").to_s.downcase
        scope = component.dig(:metadata, "scope").to_s.downcase
        case [ basis, scope ].join(" ")
        when /guest|person/
          allocations.map do |allocation|
            occupancy = allocation[:room][:occupancy].to_h
            occupancy[:adults].to_i + occupancy[:children].to_i + occupancy[:infants].to_i
          end
        when /room.?night|night/
          allocations.map { |allocation| Array(allocation[:room][:days]).size.nonzero? || 1 }
        when /per.?room|room|unit|equal/
          Array.new(allocations.size, 1.to_d)
        else
          allocations.map do |allocation|
            allocation[:room][:converted_amount].to_d / [ allocation[:room][:quantity].to_i, 1 ].max
          end
        end
      end
    end
  end
end
