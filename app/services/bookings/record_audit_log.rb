module Bookings
  class RecordAuditLog
    def self.call(...)
      new(...).call
    end

    def initialize(auditable:, user: nil, action_type: "update", old_value: nil, new_value: nil, metadata: {})
      @auditable = auditable
      @user = user
      @action_type = action_type
      @old_value = old_value
      @new_value = new_value
      @metadata = metadata
      @hotel = @auditable.respond_to?(:hotel) ? @auditable.hotel : nil
    end

    def call
      return unless @hotel

      # If values aren't provided, try to extract them from previous_changes
      if @old_value.nil? && @new_value.nil?
        changes = @auditable.previous_changes.except("updated_at", "created_at")
        return if changes.empty?

        @old_value = changes.transform_values(&:first)
        @new_value = changes.transform_values(&:last)
      end

      BookingAuditLog.create!(
        hotel: @hotel,
        auditable: @auditable,
        user: @user,
        action_type: @action_type,
        old_value: @old_value || {},
        new_value: @new_value || {},
        metadata: @metadata || {}
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create BookingAuditLog: #{e.message}"
      false
    end
  end
end
