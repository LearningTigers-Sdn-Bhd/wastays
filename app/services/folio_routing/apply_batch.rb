# frozen_string_literal: true


module FolioRouting
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
      changes = validated_changes
      return failure(@error) if @error
      child_changes = validated_child_changes
      return failure(@error) if @error
      tax_changes = validated_tax_changes
      return failure(@error) if @error
      all_changes = changes + child_changes
      impacts = preview(all_changes)
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
        return FolioRouting::BatchResult.success(transactions: []) if batch&.completed_at?
        batch ||= @booking.billing_route_batches.create!(hotel: @booking.hotel, actor: @actor, idempotency_key: @idempotency_key)
        saved_parent_rules = changes.map { |change| [ change, save_rule(change) ] }
        saved_child_rules = child_changes.map { |change| [ change, save_child_rule(change) ] }
        if @confirmation == "existing_and_future"
          saved_parent_rules.each do |_change, rule|
            result = FolioRouting::ApplyExistingCharges.call(rule:, actor: @actor, reason: @reason, confirmation: @confirmation)
            raise ActiveRecord::Rollback, (@error = result.error) unless result.success?
            moved.concat(result.transactions)
          end
          changed_parent_ids = changes.map { |change| change[:row].code.id }.to_set
          saved_child_rules.each do |change, rule|
            next if changed_parent_ids.include?(change[:row].code.id)

            movement_rule = rule || FolioRouting::TransientRule.new(booking: @booking, booking_id: @booking.id,
              transaction_code_id: change[:child].code.id, target_folio: change[:row].target_folio,
              target_folio_id: change[:row].target_folio&.id, effective_from: nil, effective_until: nil)
            result = FolioRouting::ApplyExistingCharges.call(rule: movement_rule, actor: @actor, reason: @reason, confirmation: @confirmation)
            raise ActiveRecord::Rollback, (@error = result.error) unless result.success?
            moved.concat(result.transactions)
          end
        end
        apply_tax_changes(tax_changes)
        FolioRouting::RefreshBookingForecasts.call(booking: @booking) if @forecast_confirmation == "reconcile_upcoming"
        raise ActiveRecord::Rollback if @error

        BookingAuditLog.create!(hotel: @booking.hotel, auditable: @booking, user: @actor,
          action_type: "billing_routes_changed", category: "financial", source: "booking_workspace",
          occurred_at: Time.current, new_value: { routes: @routes, confirmation: @confirmation,
            forecast_confirmation: @forecast_confirmation, reason: @reason })
        batch.update!(completed_at: Time.current)
      end
      return failure(@error) if @error

      FolioRouting::BatchResult.success(transactions: moved)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def self.preview(booking:, routes:)
      service = new(booking:, actor: nil, routes:, confirmation: nil, forecast_confirmation: nil, reason: nil)
      changes = service.send(:validated_changes)
      return FolioRouting::BatchPreview.failure(service.instance_variable_get(:@error)) if service.instance_variable_get(:@error)
      child_changes = service.send(:validated_child_changes)
      return FolioRouting::BatchPreview.failure(service.instance_variable_get(:@error)) if service.instance_variable_get(:@error)
      tax_changes = service.send(:validated_tax_changes)
      return FolioRouting::BatchPreview.failure(service.instance_variable_get(:@error)) if service.instance_variable_get(:@error)

      all_changes = changes + child_changes
      impacts = service.send(:preview, all_changes)
      upcoming = service.send(:upcoming_impact, all_changes, tax_changes)
      FolioRouting::BatchPreview.success(changes:, child_changes:, tax_changes:, impacts:,
        count: impacts.sum { |item| item[:preview].count }, amount: impacts.sum { |item| item[:preview].amount },
        upcoming_count: upcoming[:count], upcoming_amount: upcoming[:amount],
        "review_required?": impacts.any? || upcoming[:count].positive? || child_changes.any? || tax_changes.any?)
    end

    private

    def validated_changes
      matrix = RoutingMatrix.new(booking: @booking)
      rows = matrix.rows.index_by { |row| row.code.id.to_s }
      folios = matrix.folios.index_by { |folio| folio.id.to_s }
      @routes.filter_map do |code_id, attributes|
        row = rows[code_id.to_s]
        attrs = attributes.respond_to?(:to_h) ? attributes.to_h : {}
        folio = folios[attrs["target_folio_id"].to_s]
        party_id = attrs["billing_party_id"].presence
        unless row && folio
          @error = "A selected transaction code or folio is unavailable."
          next
        end
        unless folio.open?
          @error = "Billing routes can only target an open folio."
          next
        end
        unless folio.booking_billing_party_id.to_s == party_id.to_s
          @error = "Target folio must belong to the selected billing party."
          next
        end
        next if row.target_folio&.id == folio.id

        { row:, folio: }
      end
    end

    def validated_tax_changes
      rows = RoutingMatrix.new(booking: @booking).rows.index_by { |row| row.code.id.to_s }
      @routes.flat_map do |code_id, attributes|
        row = rows[code_id.to_s]
        taxes = attributes.respond_to?(:to_h) ? attributes.to_h.fetch("taxes", {}) : {}
        unless row
          @error = "A selected transaction code is unavailable."
          next []
        end
        allowed = row.children.index_by(&:key)
        taxes.filter_map do |key, value|
          unless allowed.key?(key)
            @error = "A selected tax inclusion is unavailable."
            next
          end
          included = ActiveModel::Type::Boolean.new.cast(value)
          child = allowed[key]
          next if child.included == included

          { row:, key:, included: }
        end
      end
    end

    def validated_child_changes
      matrix = RoutingMatrix.new(booking: @booking)
      rows = matrix.rows.index_by { |row| row.code.id.to_s }
      folios = matrix.folios.index_by { |folio| folio.id.to_s }
      @routes.flat_map do |code_id, attributes|
        row = rows[code_id.to_s]
        children = attributes.respond_to?(:to_h) ? attributes.to_h.fetch("children", {}) : {}
        unless row
          @error = "A selected transaction code is unavailable."
          next []
        end
        allowed = row.children.index_by(&:key)
        children.filter_map do |key, raw|
          child = allowed[key]
          attrs = raw.respond_to?(:to_h) ? raw.to_h : {}
          unless child
            @error = "A selected attached tax or charge is unavailable."
            next
          end
          choice = attrs["billing_party_choice"].presence
          mode = choice.present? ? (choice.in?(%w[inherit guest_primary_folio]) ? choice : "exception") : attrs["mode"].to_s
          party_id = choice&.delete_prefix("party:").presence || attrs["billing_party_id"].presence
          parent_party_id = attributes.to_h["billing_party_id"].to_s
          mode = "inherit" if party_id.to_s == parent_party_id
          unless mode.in?(%w[inherit exception guest_primary_folio])
            @error = "Choose whether the attached item follows its parent or uses an exception."
            next
          end
          if mode == "inherit"
            next unless child.rule
            { row:, child:, mode:, folio: row.target_folio }
          elsif mode == "guest_primary_folio"
            folio = @booking.booking_folio
            unless folio&.open?
              @error = "Guest primary folio must be open."
              next
            end
            next if child.target_folio&.id == folio.id
            { row:, child:, mode: "exception", folio: }
          else
            folio = folios[attrs["target_folio_id"].to_s]
            unless folio&.open?
              @error = "Attached-item exceptions must target an open folio."
              next
            end
            unless folio.booking_billing_party_id.to_s == party_id.to_s
              @error = "Attached-item target folio must belong to the selected billing party."
              next
            end
            next if child.target_folio&.id == folio.id
            { row:, child:, mode:, folio: }
          end
        end
      end
    end

    def preview(changes)
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
      FolioRouting::BatchResult.failure(message, transactions: [])
    end
  end
end
