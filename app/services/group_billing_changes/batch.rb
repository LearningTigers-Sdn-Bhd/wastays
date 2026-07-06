# frozen_string_literal: true

require "digest"
require "ostruct"

module GroupBillingChanges
  class Batch
    CATEGORIES = %w[accommodation fb parking other].freeze

    def self.preview(**attributes) = new(**attributes).preview
    def self.call(**attributes) = new(**attributes).call

    def initialize(group_booking:, actor:, booking_ids:, arrangement_id:, categories:, inclusion_changes: {},
      replace_local_exceptions: false, confirmation: nil, forecast_confirmation: nil, reason: nil,
      idempotency_key: nil, freshness_token: nil)
      @group = group_booking
      @hotel = group_booking.hotel
      @actor = actor
      @booking_ids = Array(booking_ids).map(&:to_i).uniq.sort
      @arrangement_id = arrangement_id.to_i
      @categories = Array(categories).map(&:to_s).uniq.sort
      @inclusion_changes = inclusion_changes.to_h
      @replace_local_exceptions = ActiveModel::Type::Boolean.new.cast(replace_local_exceptions)
      @confirmation = confirmation.to_s
      @forecast_confirmation = forecast_confirmation.to_s
      @reason = reason.to_s.strip
      @idempotency_key = idempotency_key.to_s
      @freshness_token = freshness_token.to_s
    end

    def preview
      error = validate_request
      return failure(error) if error

      rows = bookings.map { |booking| preview_booking(booking) }
      payload = canonical_payload
      OpenStruct.new(success?: true, bookings: rows, count: rows.sum { |row| row[:count] },
        amount: rows.sum { |row| row[:amount] }, upcoming_count: rows.sum { |row| row[:upcoming_count] },
        upcoming_amount: rows.sum { |row| row[:upcoming_amount] }, skipped_exceptions: skipped_exceptions,
        freshness_token: digest(payload.merge(state: state_snapshot)), payload_digest: digest(payload), review_required?: true,
        arrangement: arrangement, categories: @categories)
    end

    def call
      current = preview
      return current unless current.success?
      completed = @group.group_billing_change_batches.find_by(idempotency_key: @idempotency_key, status: "completed")
      if completed
        return failure("This idempotency key was already used for a different group billing change.") if completed.payload_digest != current.payload_digest
        return success([])
      end
      return failure("Review is stale. Preview the latest group billing impact and try again.") unless secure_match?(current.freshness_token, @freshness_token)
      return failure("Reason is required for a group billing change.") if @reason.blank?
      return failure("Choose how to handle existing charges.") unless @confirmation.in?(%w[existing_and_future future_only])
      if current.upcoming_count.positive? && !@forecast_confirmation.in?(%w[reconcile_upcoming leave_upcoming])
        return failure("Choose how to handle upcoming charges.")
      end
      return failure("This group billing request is missing its idempotency key.") if @idempotency_key.blank?

      moved = []
      ActiveRecord::Base.transaction do
        @group.lock!
        batch = @group.group_billing_change_batches.find_by(idempotency_key: @idempotency_key)
        return success([]) if batch&.completed_at?
        if batch && batch.payload_digest != current.payload_digest
          raise ActiveRecord::Rollback, (@error = "This idempotency key was already used for a different group billing change.")
        end
        batch ||= @group.group_billing_change_batches.create!(hotel: @hotel, actor: @actor,
          idempotency_key: @idempotency_key, payload_digest: current.payload_digest)

        bookings.sort_by(&:id).each do |booking|
          booking.lock!
          apply_booking!(booking, moved)
        end
        record_group_audit!
        batch.update!(status: "completed", completed_at: Time.current)
      end
      return failure(@error) if @error

      success(moved)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_request
      return "Select at least one child booking." if @booking_ids.empty?
      return "Select at least one supported charge category." if @categories.empty?
      return "One or more selected charge categories are unavailable." unless (@categories - CATEGORIES).empty?
      return "Select an active group billing arrangement." unless arrangement
      return "Every selected booking must belong to this group and hotel." unless bookings.size == @booking_ids.size
      return "The selected arrangement belongs to another hotel." unless arrangement.hotel_id == @hotel.id
      nil
    end

    def arrangement
      @arrangement ||= @group.group_billing_arrangements.active.find_by(id: @arrangement_id)
    end

    def bookings
      @bookings ||= @group.bookings.where(id: @booking_ids).includes(:booking_billing_assignments,
        :folio_routing_rules, :booking_tax_inclusion_overrides, booking_folios: :booking_billing_party).to_a
    end

    def codes
      @codes ||= FolioRouting::RoutabilityPolicy.parent_codes(hotel: @hotel).where(category: @categories).to_a
    end

    def skipped_exceptions
      return [] if @replace_local_exceptions
      bookings.flat_map do |booking|
        booking.booking_billing_assignments.select { |item| item.local_exception? && item.charge_category.in?(@categories) }
      end
    end

    def preview_booking(booking)
      target = target_folio_for(booking, create: false)
      impacts = codes.filter_map do |code|
        rule = booking.folio_routing_rules.active.find_by(transaction_code: code)
        next if preserve_local_rule?(rule)
        temporary = rule || FolioRoutingRule.new(booking: booking, hotel: @hotel,
          transaction_code: code, source_type: "group")
        temporary.target_folio = target
        result = FolioRouting::PreviewExistingCharges.call(rule: temporary)
        { code: code, from: rule&.target_folio || booking.booking_folio, to: target, preview: result }
      end
      forecasts = FolioForecastedCharge.forecast.where(booking_folio_id: booking.booking_folios.select(:id))
      { booking: booking, target_folio: target, impacts: impacts, count: impacts.sum { |item| item[:preview].count },
        amount: impacts.sum { |item| item[:preview].amount }, upcoming_count: forecasts.count,
        upcoming_amount: forecasts.sum(:amount) }
    end

    def apply_booking!(booking, moved)
      moved_before = moved.length
      assignments = apply_assignments!(booking)
      target = target_folio_for(booking, create: true)
      codes.each do |code|
        existing = booking.folio_routing_rules.active.find_by(transaction_code: code)
        next if preserve_local_rule?(existing)
        existing&.update!(active: false, updated_by: @actor) if existing&.source_type == "booking"
        assignment = assignments.find { |item| item.charge_category == code.category }
        rule = existing&.source_type == "group" ? existing : booking.folio_routing_rules.build(
          hotel: @hotel, transaction_code: code, source_type: "group", created_by: @actor)
        rule.assign_attributes(target_folio: target, active: true, group_billing_arrangement: arrangement,
          booking_billing_assignment: assignment, updated_by: @actor,
          effective_from: assignment&.effective_from, effective_until: assignment&.effective_until)
        rule.save!
        next unless @confirmation == "existing_and_future"
        movement = FolioRouting::ApplyExistingCharges.call(rule: rule, actor: @actor, reason: @reason,
          confirmation: @confirmation)
        raise ActiveRecord::Rollback, (@error = movement.error) unless movement.success?
        moved.concat(movement.transactions)
      end
      apply_inclusions!(booking)
      FolioRouting::RefreshBookingForecasts.call(booking: booking) if @forecast_confirmation == "reconcile_upcoming"
      record_booking_audit!(booking, target, moved.drop(moved_before))
    end

    def apply_assignments!(booking)
      @categories.filter_map do |category|
        assignment = booking.booking_billing_assignments.find_or_initialize_by(charge_category: category)
        next if assignment.persisted? && assignment.local_exception? && !@replace_local_exceptions
        assignment.assign_attributes(group_billing_arrangement: arrangement, local_exception: false)
        assignment.save!
        assignment
      end
    end

    def target_folio_for(booking, create:)
      if arrangement.payer_type == "company"
        unless create
          return booking.booking_folios.find do |folio|
            folio.hotel_corporate_account_id == arrangement.hotel_corporate_account_id && folio.open?
          end
        end
        result = Billing::EnsureCorporateFolio.call(booking: booking, arrangement: arrangement, actor: @actor)
        raise result.error if create && !result.success?
        raise "Group billing routes require an open child-booking folio." unless result.folio&.open?
        result.folio
      else
        BookingBillingParties::EnsureForBooking.call(booking: booking, actor: @actor) if create
        folio = booking.booking_folio
        folio = nil unless folio&.open?
        folio ||= booking.booking_folios.find(&:open?)
        raise "Group billing routes require an open child-booking folio." if create && folio.blank?
        folio
      end
    end

    def preserve_local_rule?(rule)
      rule&.source_type == "booking" && !@replace_local_exceptions
    end

    def apply_inclusions!(booking)
      @inclusion_changes.each do |code_id, changes|
        code = codes.find { |candidate| candidate.id.to_s == code_id.to_s }
        next unless code
        changes.to_h.each do |key, value|
          next unless value.to_s.in?(%w[include exclude])
          included = value.to_s == "include"
          scope = booking.booking_tax_inclusion_overrides.where(transaction_code: code)
          attributes = { hotel: @hotel, actor: @actor, action: included ? "include" : "exclude", reason: @reason }
          override = if key.start_with?("primary:")
            scope.find_or_initialize_by(primary_tax_key: key.delete_prefix("primary:"))
          else
            scope.find_or_initialize_by(hotel_tax_id: key.delete_prefix("hotel_tax:"))
          end
          override.assign_attributes(attributes)
          override.save!
        end
      end
    end

    def record_booking_audit!(booking, target, moved)
      BookingAuditLog.create!(hotel: @hotel, auditable: booking, user: @actor,
        action_type: "group_billing_routes_changed", category: "financial", source: "booking_control_panel",
        occurred_at: Time.current, new_value: { group_booking_id: @group.id, arrangement_id: arrangement.id,
          categories: @categories, target_folio_id: target&.id, moved_transaction_ids: moved.map(&:id),
          inclusion_changes: @inclusion_changes, reason: @reason })
    end

    def record_group_audit!
      BookingAuditLog.create!(hotel: @hotel, auditable: @group, user: @actor,
        action_type: "group_billing_change_applied", category: "financial", source: "booking_control_panel",
        occurred_at: Time.current, new_value: { booking_ids: @booking_ids, arrangement_id: arrangement.id,
          categories: @categories, inclusion_changes: @inclusion_changes, reason: @reason })
    end

    def canonical_payload
      { group_booking_id: @group.id, booking_ids: @booking_ids, arrangement_id: @arrangement_id,
        categories: @categories, inclusion_changes: @inclusion_changes.deep_stringify_keys.sort.to_h,
        replace_local_exceptions: @replace_local_exceptions }
    end

    def state_snapshot
      bookings.sort_by(&:id).map do |booking|
        {
          booking_id: booking.id,
          booking_updated_at: booking.updated_at&.iso8601(6),
          assignments: booking.booking_billing_assignments.sort_by(&:id).map { |item| [ item.id, item.updated_at&.iso8601(6), item.local_exception ] },
          folios: booking.booking_folios.sort_by(&:id).map { |folio| [ folio.id, folio.status, folio.updated_at&.iso8601(6) ] },
          rules: booking.folio_routing_rules.select(&:persisted?).sort_by(&:id).map { |rule| [ rule.id, rule.active, rule.target_folio_id, rule.updated_at&.iso8601(6) ] },
          overrides: booking.booking_tax_inclusion_overrides.sort_by(&:id).map { |item| [ item.id, item.action, item.updated_at&.iso8601(6) ] }
        }
      end
    end

    def digest(value) = Digest::SHA256.hexdigest(value.to_json)
    def secure_match?(left, right) = left.present? && right.present? && ActiveSupport::SecurityUtils.secure_compare(left, right)
    def success(transactions) = OpenStruct.new(success?: true, transactions: transactions, error: nil)
    def failure(error) = OpenStruct.new(success?: false, error: error)
  end
end
