# frozen_string_literal: true

module NightAudits
  class PublishStaffNotification
    PERMISSION = "manage_night_audit".freeze

    def self.call(night_audit:)
      new(night_audit:).call
    end

    def initialize(night_audit:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
    end

    def call
      return resolve_notifications if @night_audit.completed?
      return true unless action_required?

      recipients.find_each { |access| publish_for(access.user) }
      true
    rescue StandardError => error
      log_failure(error)
      false
    end

    private

    def recipients
      @hotel.user_hotel_accesses.active
        .joins(role: :permissions)
        .includes(:user)
        .where(permissions: { slug: PERMISSION })
        .distinct
    end

    def publish_for(user, retried: false)
      key = deduplication_key(user)
      notification = StaffNotification.find_or_initialize_by(deduplication_key: key)
      notification.assign_attributes(attributes_for(user))
      # Staff already read the old message. A changed message is a new problem,
      # so the bell has to light up again.
      notification.read_at = nil if notification.persisted? && notification.changed?
      notification.save!
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      # Two runs can reach the same key together. The loser reloads the row the
      # winner wrote and updates it. One retry only.
      return log_failure(error, user:) if retried || !StaffNotification.exists?(deduplication_key: key)

      publish_for(user, retried: true)
    rescue StandardError => error
      log_failure(error, user:)
    end

    def attributes_for(user)
      {
        hotel: @hotel,
        recipient: user,
        subject: @night_audit,
        notification_type: notification_type,
        severity: severity,
        title: title,
        message: message,
        action_path: action_path,
        metadata: {
          "business_date" => @night_audit.business_date.iso8601,
          "blocker_count" => blocker_count
        },
        resolved_at: nil
      }
    end

    def log_failure(error, user: nil)
      recipient = user ? " recipient #{user.id}" : ""
      Rails.logger.error(
        "Failed to publish staff notification for Night Audit #{@night_audit.id}#{recipient}: #{error.message}"
      )
    end

    def resolve_notifications
      now = Time.current
      @night_audit.staff_notifications.active.update_all(resolved_at: now, updated_at: now)
      true
    end

    def deduplication_key(user)
      "night_audit:#{@night_audit.id}:recipient:#{user.id}"
    end

    def notification_type
      @night_audit.failed? ? "night_audit_failed" : "night_audit_action_required"
    end

    def action_required?
      @night_audit.failed? || @night_audit.blocked? ||
        (@night_audit.preparing? && blocker_count.positive?)
    end

    def severity
      @night_audit.failed? ? "critical" : "warning"
    end

    def title
      @night_audit.failed? ? "Night Audit did not finish" : "Night Audit needs attention"
    end

    def message
      date = @night_audit.business_date.strftime("%d %b %Y")
      return "A processing error stopped Night Audit for #{date}. The business date did not change." if @night_audit.failed?

      "Night Audit found items that need attention for #{date}. The business date did not change."
    end

    def action_path
      Rails.application.routes.url_helpers.hotel_night_audit_run_path(@hotel)
    end

    def blocker_count
      @night_audit.blocked_details.to_h.values.sum { |items| Array(items).size }
    end
  end
end
