# frozen_string_literal: true


module Folios
  module Routing
    class ApplyBatch
      def self.call(booking:, actor:, routes:, confirmation:, forecast_confirmation: nil, reason:, idempotency_key:)
        new(booking:, actor:, routes:, confirmation:, forecast_confirmation:, reason:, idempotency_key:).call
      end

      def initialize(booking:, actor:, routes:, confirmation:, forecast_confirmation: nil, reason:, idempotency_key: nil)
        @booking = booking
        @actor = actor
        @routes = routes.to_h
        @confirmation = confirmation.to_s
        @forecast_confirmation = forecast_confirmation.to_s
        @reason = reason.to_s.strip
        @idempotency_key = idempotency_key.to_s
      end

      def call
        return failure(change_set.error) unless change_set.valid?

        changes = change_set.changes
        child_changes = change_set.child_changes
        tax_changes = change_set.tax_changes
        all_changes = change_set.all_changes
        impacts = impacts_for(all_changes)
        upcoming = upcoming_impact(all_changes, tax_changes)
        if impacts.any? && !@confirmation.in?(%w[existing_and_future future_only])
          return failure("Choose how to handle existing charges.")
        end
        if upcoming[:count].positive? && !@forecast_confirmation.in?(%w[reconcile_upcoming leave_upcoming])
          return failure("Choose how to handle upcoming charges.")
        end
        needs_reason = impacts.any? || child_changes.any? || tax_changes.any? || upcoming[:count].positive?
        return failure("Reason is required for this billing change.") if needs_reason && @reason.blank?
        return failure("This billing-route request is missing its idempotency key.") if @idempotency_key.blank?

        moved = []
        FolioRoutingRule.transaction do
          @booking.lock!
          batch = @booking.billing_route_batches.find_by(idempotency_key: @idempotency_key)
          return Folios::Routing::BatchResult.success(transactions: []) if batch&.completed_at?
          batch ||= @booking.billing_route_batches.create!(hotel: @booking.hotel, actor: @actor, idempotency_key: @idempotency_key)
          saved_parent_rules = changes.map { |change| [ change, save_rule(change) ] }
          saved_child_rules = child_changes.map { |change| [ change, save_child_rule(change) ] }
          if @confirmation == "existing_and_future"
            saved_parent_rules.each do |_change, rule|
              result = Folios::Routing::ApplyExistingCharges.call(rule:, actor: @actor, reason: @reason, confirmation: @confirmation)
              raise ActiveRecord::Rollback, (@error = result.error) unless result.success?
              moved.concat(result.transactions)
            end
            changed_parent_ids = changes.map { |change| change[:row].code.id }.to_set
            saved_child_rules.each do |change, rule|
              next if changed_parent_ids.include?(change[:row].code.id)

              movement_rule = rule || Folios::Routing::TransientRule.new(booking: @booking, booking_id: @booking.id,
                transaction_code_id: change[:child].code.id, target_folio: change[:row].target_folio,
                target_folio_id: change[:row].target_folio&.id, effective_from: nil, effective_until: nil)
              result = Folios::Routing::ApplyExistingCharges.call(rule: movement_rule, actor: @actor, reason: @reason, confirmation: @confirmation)
              raise ActiveRecord::Rollback, (@error = result.error) unless result.success?
              moved.concat(result.transactions)
            end
          end
          apply_tax_changes(tax_changes)
          Folios::Routing::RefreshBookingForecasts.call(booking: @booking) if @forecast_confirmation == "reconcile_upcoming"
          raise ActiveRecord::Rollback if @error

          BookingAuditLog.create!(hotel: @booking.hotel, auditable: @booking, user: @actor,
            action_type: "billing_routes_changed", category: "financial", source: "booking_workspace",
            occurred_at: Time.current, new_value: { routes: @routes, confirmation: @confirmation,
              forecast_confirmation: @forecast_confirmation, reason: @reason })
          batch.update!(completed_at: Time.current)
        end
        return failure(@error) if @error

        Folios::Routing::BatchResult.success(transactions: moved)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages.to_sentence)
      end

      def self.preview(booking:, routes:)
        new(booking:, actor: nil, routes:, confirmation: nil, forecast_confirmation: nil, reason: nil).preview
      end

      def preview
        return Folios::Routing::BatchPreview.failure(change_set.error) unless change_set.valid?

        changes = change_set.changes
        child_changes = change_set.child_changes
        tax_changes = change_set.tax_changes
        all_changes = change_set.all_changes
        impacts = impacts_for(all_changes)
        upcoming = upcoming_impact(all_changes, tax_changes)
        Folios::Routing::BatchPreview.success(changes:, child_changes:, tax_changes:, impacts:,
          count: impacts.sum { |item| item[:preview].count }, amount: impacts.sum { |item| item[:preview].amount },
          upcoming_count: upcoming[:count], upcoming_amount: upcoming[:amount],
          "review_required?": impacts.any? || upcoming[:count].positive? || child_changes.any? || tax_changes.any?)
      end

      private

      def change_set
        @change_set ||= Folios::Routing::RoutingChangeSet.build(booking: @booking, routes: @routes)
      end

      def impacts_for(changes)
        changes.filter_map do |change|
          temporary_rule = change[:row].rule || @booking.folio_routing_rules.build(
            hotel: @booking.hotel, transaction_code: change[:row].code, target_folio: change[:folio], source_type: "booking"
          )
          temporary_rule.target_folio = change[:folio]
          result = PreviewExistingCharges.call(rule: temporary_rule)
          { change:, preview: result } if result.count.positive?
        end
      end

      def save_rule(change)
        existing = change[:row].rule
        existing.update!(active: false, updated_by: @actor) if existing&.source_type == "group"
        rule = existing&.source_type == "booking" ? existing : @booking.folio_routing_rules.build(
          hotel: @booking.hotel, transaction_code: change[:row].code, source_type: "booking", created_by: @actor
        )
        rule.assign_attributes(target_folio: change[:folio], active: true, updated_by: @actor)
        rule.save!
        rule
      end

      def save_child_rule(change)
        existing = change[:child].rule
        if change[:mode] == "inherit"
          existing&.update!(active: false, updated_by: @actor)
          return nil
        end

        existing.update!(active: false, updated_by: @actor) if existing&.source_type == "group"
        rule = existing&.source_type == "booking" ? existing : @booking.folio_routing_rules.build(
          hotel: @booking.hotel, transaction_code: change[:child].code, source_type: "booking", created_by: @actor
        )
        rule.assign_attributes(target_folio: change[:folio], active: true, updated_by: @actor)
        rule.save!
        rule
      end

      def upcoming_impact(changes, tax_changes)
        return { count: 0, amount: 0.to_d } if changes.empty? && tax_changes.empty?

        forecasts = FolioForecastedCharge.forecast.where(booking_folio_id: @booking.booking_folios.select(:id))
        { count: forecasts.count, amount: forecasts.sum(:amount) }
      end

      def apply_tax_changes(changes)
        changes.each do |change|
          scope = @booking.booking_tax_inclusion_overrides.where(transaction_code: change[:row].code)
          attributes = { hotel: @booking.hotel, actor: @actor, action: change[:included] ? "include" : "exclude", reason: @reason }
          if change[:key].start_with?("primary:")
            attributes[:primary_tax_key] = change[:key].delete_prefix("primary:")
            override = scope.find_or_initialize_by(primary_tax_key: attributes[:primary_tax_key])
          else
            attributes[:hotel_tax_id] = change[:key].delete_prefix("hotel_tax:")
            override = scope.find_or_initialize_by(hotel_tax_id: attributes[:hotel_tax_id])
          end
          override.assign_attributes(attributes)
          override.save!
        end
      end

      def failure(message)
        Folios::Routing::BatchResult.failure(message, transactions: [])
      end
    end
  end
end
