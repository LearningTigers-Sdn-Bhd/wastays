# frozen_string_literal: true

require "ostruct"

module Folios
  class ResolveTargetFolio
    PERMISSION = "manage_folio_movements"

    def self.call(booking:, transaction_code:, parent_transaction: nil, fallback_transaction_code: nil, override_target_folio: nil, override_reason: nil, actor: nil, permission_context: nil)
      new(
        booking: booking,
        transaction_code: transaction_code,
        parent_transaction: parent_transaction,
        fallback_transaction_code: fallback_transaction_code,
        override_target_folio: override_target_folio,
        override_reason: override_reason,
        actor: actor,
        permission_context: permission_context
      ).call
    end

    def initialize(booking:, transaction_code:, parent_transaction: nil, fallback_transaction_code: nil, override_target_folio: nil, override_reason: nil, actor: nil, permission_context: nil)
      @booking = booking
      @hotel = booking&.hotel
      @transaction_code = transaction_code
      @parent_transaction = parent_transaction
      @fallback_transaction_code = fallback_transaction_code
      @override_target_folio = override_target_folio
      @override_reason = override_reason.to_s.strip
      @actor = actor
      @permission_context = permission_context || actor
    end

    def call
      folio, source, metadata, error = resolve
      return failure(error, source: source, metadata: metadata) if error.present?

      validation_error = validate_resolved_folio(folio)
      return failure(validation_error, source: source, metadata: metadata) if validation_error.present?

      success(folio, source, metadata)
    end

    private

    def resolve
      return parent_route if @parent_transaction.present?
      return override_route if @override_target_folio.present?
      return rule_route if active_rule.present?
      return fallback_route if valid_fallback_transaction_code?

      [ @booking&.booking_folio, "primary_folio", {}, nil ]
    end

    def parent_route
      error = validate_parent_transaction
      metadata = {
        parent_transaction_id: @parent_transaction.id,
        parent_transaction_code_id: @parent_transaction.transaction_code_id,
        parent_transaction_code_code: @parent_transaction.transaction_code&.code
      }.compact
      return [ nil, "follows_parent", metadata, error ] if error.present?

      [ @parent_transaction.booking_folio, "follows_parent", metadata, nil ]
    end

    def override_route
      return [ @override_target_folio, "manual_override", override_metadata, "Override reason can't be blank." ] if @override_reason.blank?
      return [ @override_target_folio, "manual_override", override_metadata, "You do not have permission to override folio routing." ] unless permitted?

      [ @override_target_folio, "manual_override", override_metadata, nil ]
    end

    def rule_route
      [ active_rule.target_folio, "routing_rule", { folio_routing_rule_id: active_rule.id }, nil ]
    end

    def fallback_route
      route = self.class.call(
        booking: @booking,
        transaction_code: @fallback_transaction_code,
        actor: @actor,
        permission_context: @permission_context
      )
      metadata = {
        fallback_transaction_code_id: @fallback_transaction_code.id,
        fallback_transaction_code_code: @fallback_transaction_code.code,
        inherited_route_source: route.route_source,
        inherited_route_metadata: route.route_metadata
      }.compact

      return [ nil, "follows_parent", metadata, route.error ] unless route.success?

      [ route.folio, "follows_parent", metadata, nil ]
    end

    def valid_fallback_transaction_code?
      @fallback_transaction_code.present? && @fallback_transaction_code.id != @transaction_code&.id
    end

    def active_rule
      return if @booking.blank? || @transaction_code.blank?

      @active_rule ||= @booking.folio_routing_rules.active.includes(:target_folio).find_by(transaction_code: @transaction_code)
    end

    def validate_parent_transaction
      parent_folio = @parent_transaction.booking_folio
      return "Parent transaction must belong to a folio." if parent_folio.blank?
      return "Parent transaction must belong to the same booking." unless parent_folio.booking_id == @booking&.id
      return "Parent transaction must belong to the same hotel." unless parent_folio.hotel_id == @hotel&.id

      nil
    end

    def validate_resolved_folio(folio)
      return "Resolved folio is not available." if folio.blank?
      return "Resolved folio must belong to the booking." unless folio.booking_id == @booking&.id
      return "Resolved folio must belong to the hotel." unless folio.hotel_id == @hotel&.id
      return "Resolved folio must be open." unless folio.open?

      nil
    end

    def override_metadata
      {
        override_target_folio_id: @override_target_folio&.id,
        override_reason: @override_reason.presence,
        override_actor_id: @actor&.id
      }.compact
    end

    def permitted?
      @permission_context&.respond_to?(:superadmin?) && @permission_context.superadmin? ||
        @permission_context&.respond_to?(:has_permission?) && @permission_context.has_permission?(PERMISSION, hotel: @hotel)
    end

    def success(folio, source, metadata)
      OpenStruct.new(success?: true, folio: folio, route_source: source, route_metadata: metadata, error: nil)
    end

    def failure(error, source:, metadata: {})
      OpenStruct.new(success?: false, folio: nil, route_source: source, route_metadata: metadata || {}, error: error)
    end
  end
end
