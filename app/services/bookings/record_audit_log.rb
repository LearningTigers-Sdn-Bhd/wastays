module Bookings
  class RecordAuditLog
    ACTION_CATEGORIES = {
      "create" => "stay",
      "external_creation" => "stay",
      "external_modification" => "stay",
      "update" => "stay",
      "status_change" => "status",
      "check_in" => "status",
      "check_out" => "status",
      "cancel" => "status",
      "reinstate" => "status",
      "no_show" => "status",
      "room_assignment" => "room",
      "room_removed" => "room",
      "charge_added" => "financial",
      "payment_recorded" => "financial",
      "refund_completed" => "financial",
      "payout_processing" => "financial",
      "note_added" => "notes",
      "note_updated" => "notes",
      "note_deleted" => "notes",
      "pre_checkin_completed" => "stay",
      "pre_checkin_updated" => "stay",
      "guest_added" => "stay",
      "guest_updated" => "stay",
      "guest_removed" => "stay"
    }.freeze

    def self.call(**kwargs)
      new(**kwargs, allow_empty: false).call!
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      Rails.logger.error "Failed to create BookingAuditLog: #{e.message}"
      false
    end

    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def initialize(auditable:, user: nil, action_type: "update", category: nil, source: nil, old_value: nil, new_value: nil,
      reason: nil, metadata: {}, occurred_at: Time.current, allow_empty: true)
      @auditable = auditable
      @user = user
      @action_type = action_type
      @category = category.presence || ACTION_CATEGORIES.fetch(action_type.to_s, "other")
      @source = source.presence || default_source
      @old_value = old_value
      @new_value = new_value
      @metadata = (metadata || {}).deep_stringify_keys
      @metadata["reason"] = reason if reason.present?
      @occurred_at = occurred_at
      @allow_empty = allow_empty
      @hotel = @auditable.respond_to?(:hotel) ? @auditable.hotel : nil
    end

    def call!
      raise ArgumentError, "Auditable must belong to a hotel" unless @hotel

      # If values aren't provided, try to extract them from previous_changes
      if @old_value.nil? && @new_value.nil?
        changes = @auditable.previous_changes.except("updated_at", "created_at")
        return if changes.empty? && !@allow_empty
        changes = { "event" => [ nil, @action_type ] } if changes.empty?

        @old_value = changes.transform_values(&:first)
        @new_value = changes.transform_values(&:last)
      end

      BookingAuditLog.create!(
        hotel: @hotel,
        auditable: @auditable,
        user: @user,
        action_type: @action_type,
        category: @category,
        source: @source,
        request_id: Current.request_id,
        occurred_at: @occurred_at,
        old_value: @old_value || {},
        new_value: @new_value || {},
        metadata: @metadata || {}
      )
    end

    private

    def default_source
      return "staff" if @user.present?
      return "channel_manager" if @action_type.to_s.start_with?("external_")
      return "guest" if @action_type.to_s.in?(%w[create convert pre_checkin_completed])

      "system"
    end
  end
end
