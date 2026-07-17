# frozen_string_literal: true

module HotelPortal
  class BookingAuditLogPresenter
    STATUS_LABELS = {
      "pending" => "Pending",
      "confirmed" => "Confirmed",
      "review_no_show" => "Pending no-show review",
      "checked_in" => "Checked in",
      "review_due_out" => "Pending late-checkout review",
      "cancelled" => "Cancelled",
      "completed" => "Checked out",
      "overbooked" => "Overbooked",
      "no_show" => "No-show"
    }.freeze

    FIELD_LABELS = {
      "status" => "Booking status",
      "guest_name" => "Guest name",
      "guest_email" => "Guest email",
      "guest_phone" => "Guest phone",
      "guest_country" => "Guest country",
      "check_in" => "Check-in",
      "check_out" => "Check-out",
      "checked_in_at" => "Check-in time",
      "checked_out_at" => "Check-out time",
      "adults" => "Adults",
      "children" => "Children",
      "room_number" => "Room number",
      "room_category" => "Room category",
      "rate_plan" => "Rate plan",
      "room_type_id" => "Room category",
      "rate_plan_id" => "Rate plan",
      "total_amount" => "Booking total",
      "payment_status" => "Payment status",
      "deposit_status" => "Deposit status",
      "guarantee_method" => "Guarantee method",
      "pre_checkin_status" => "Pre-check-in status",
      "rooms" => "Rooms",
      "body" => "Note"
    }.freeze

    HIDDEN_FIELDS = %w[
      id hotel_id booking_id booking_quote_id updated_at created_at revision_number
      hotel_snapshot room_type_snapshot nightly_rate_snapshot tax_lines tax_posting_snapshot
      confirmation_token guest_registration_number event
    ].freeze

    SENSITIVE_FIELDS = %w[
      email guest_email email_snapshot guest_email_snapshot
      phone guest_phone phone_snapshot guest_phone_snapshot
      government_id government_id_snapshot guest_government_id
      date_of_birth date_of_birth_snapshot guest_date_of_birth
      home_address guest_home_address body
    ].freeze
    SENSITIVE_FIELD_PATTERN = /(api[_-]?key|(?:^|[_-])key(?:$|[_-])|secret|token|password|credential|authorization|private[_-]?key)/i

    attr_reader :log, :hotel

    delegate :id, :action_type, :category, :source, :metadata, to: :log

    def initialize(log, hotel:)
      @log = log
      @hotel = hotel
    end

    def title
      {
        "create" => "Booking created",
        "external_creation" => "Channel booking received",
        "external_modification" => "Channel booking updated",
        "update" => "Booking details updated",
        "status_change" => status_change_title,
        "check_in" => "Guest checked in",
        "check_out" => "Guest checked out",
        "cancel" => "Booking cancelled",
        "reinstate" => "No-show booking reinstated",
        "no_show" => automatic? ? "Booking automatically marked as no-show" : "Booking marked as no-show",
        "room_assignment" => "Room assignment updated",
        "room_removed" => "Room assignment removed",
        "note_added" => "Internal note added",
        "note_updated" => "Internal note updated",
        "note_deleted" => "Internal note deleted",
        "charge_added" => "Charge added",
        "payment_recorded" => "Payment recorded",
        "refund_completed" => "Refund completed",
        "payout_processing" => "Payout processing started",
        "pre_checkin_completed" => "Guest completed pre-check-in",
        "pre_checkin_updated" => "Pre-check-in progress updated",
        "guest_added" => "Guest added",
        "guest_updated" => "Guest details updated",
        "guest_removed" => "Guest removed",
        "convert" => "Quote converted into booking",
        "expire" => "Quote expired"
      }.fetch(action_type, action_type.to_s.humanize)
    end

    def summary
      case action_type
      when "check_in"
        "#{actor_name} checked #{guest_name} in#{room_suffix}."
      when "check_out"
        "#{actor_name} checked #{guest_name} out."
      when "cancel"
        "#{actor_name} cancelled the booking."
      when "reinstate"
        "#{actor_name} reinstated the no-show booking and checked the guest in."
      when "no_show"
        automatic? ? "The system finalized the booking as a no-show." : "#{actor_name} marked the booking as a no-show."
      when "room_assignment"
        "#{actor_name} assigned #{room_label}."
      when "status_change"
        "Booking moved from #{status_label(from_status)} to #{status_label(to_status)}."
      when "external_creation"
        "A new booking was received from #{source_label}."
      when "external_modification"
        "Booking details were updated by #{source_label}."
      when "create"
        "#{actor_name} created the booking."
      when "update"
        "#{actor_name} updated the booking details."
      when "note_added", "note_updated", "note_deleted"
        "#{actor_name} #{action_type.delete_prefix('note_')} an internal note."
      when "pre_checkin_completed"
        "The guest completed pre-check-in."
      when "pre_checkin_updated"
        "Pre-check-in progress was updated by #{source_label}."
      when "guest_added"
        "#{actor_name} added a guest to the booking."
      when "guest_updated"
        "#{actor_name} updated guest details."
      when "guest_removed"
        "#{actor_name} removed a guest from the booking."
      when "refund_completed"
        "#{actor_name} completed the booking refund."
      when "payout_processing"
        "The system added the booking to a payout batch."
      else
        "#{actor_name} recorded #{title.downcase}."
      end
    end

    def actor_name
      return log.user.name if log.user.present?

      source_label
    end

    def source_label
      {
        "staff" => "Staff",
        "guest" => "Guest",
        "night_audit" => "Night Audit",
        "channel_manager" => channel_source,
        "system" => "System",
        "legacy" => "Legacy record"
      }.fetch(source.to_s, source.to_s.humanize.presence || "System")
    end

    def occurred_at_label
      timestamp = log.occurred_at || log.created_at
      timestamp.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %I:%M %p")
    end

    def context_details
      [
        [ "Reason", reason ],
        [ "Source", context_source ],
        [ "Business date", metadata["business_date"] ],
        [ "External reference", metadata["external_reference"] ],
        [ "Folio", metadata["folio_number"] ],
        [ "Outstanding balance", metadata["outstanding_balance"] ],
        [ "Security deposit", metadata["security_deposit_amount"] ]
      ].filter_map { |label, value| [ label, value ] if value.present? }
    end

    def formatted_changes
      fields = (old_values.keys | new_values.keys) - HIDDEN_FIELDS
      fields.filter_map do |field|
        next if field.end_with?("_id", "_at")

        old_value = old_values[field]
        new_value = new_values[field]
        next if old_value == new_value

        {
          field: FIELD_LABELS.fetch(field, field.humanize),
          old: format_value(field, old_value),
          new: format_value(field, new_value)
        }
      end
    end

    def icon
      log.action_icon
    end

    def color
      log.action_color
    end

    private

    def booking
      @booking ||= case log.auditable
      when Booking then log.auditable
      when BookingRoom then log.auditable.booking
      end
    end

    def guest_name
      booking&.guest_name.presence || "the guest"
    end

    def room_label
      room_number = new_values["room_number"].presence || metadata["room_number"].presence ||
        (log.auditable.room_number if log.auditable.is_a?(BookingRoom))
      room_number.present? ? "Room #{room_number}" : "a room"
    end

    def room_suffix
      room_label == "a room" ? "" : " to #{room_label}"
    end

    def status_change_title
      to_status.present? ? "Booking moved to #{status_label(to_status)}" : "Booking status changed"
    end

    def from_status
      metadata["from"].presence || old_values["status"]
    end

    def to_status
      metadata["to"].presence || new_values["status"]
    end

    def status_label(value)
      STATUS_LABELS.fetch(value.to_s, value.to_s.humanize.presence || "Not provided")
    end

    def automatic?
      ActiveModel::Type::Boolean.new.cast(metadata["automatic"])
    end

    def reason
      metadata["reason"].presence || metadata["retroactive_reason"].presence ||
        metadata["backdate_reason_details"].presence || metadata["backdate_reason_category"].presence
    end

    def context_source
      return channel_source if source == "channel_manager"
      source_label if source.in?(%w[night_audit guest system])
    end

    def channel_source
      metadata["source"].presence || "Channel manager"
    end

    def old_values
      log.old_value.is_a?(Hash) ? log.old_value : {}
    end

    def new_values
      log.new_value.is_a?(Hash) ? log.new_value : {}
    end

    def format_value(field, value)
      return "Not provided" if value.blank?
      return "Redacted" if field.in?(SENSITIVE_FIELDS) || field.match?(SENSITIVE_FIELD_PATTERN)
      return status_label(value) if field == "status"
      return value ? "Yes" : "No" if value.in?([ true, false ])
      return format_time(value) if field.in?(%w[check_in check_out checked_in_at checked_out_at])
      return format_money(value) if field.in?(%w[total_amount])
      return value.join(", ") if field == "rooms" && value.is_a?(Array)
      return "#{value.size} items" if value.is_a?(Array)
      return "Updated details" if value.is_a?(Hash)

      value.to_s.humanize
    end

    def format_time(value)
      Time.zone.parse(value.to_s).in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %I:%M %p")
    rescue ArgumentError, NoMethodError
      value.to_s
    end

    def format_money(value)
      ActionController::Base.helpers.number_to_currency(value, unit: "#{booking&.currency || 'MYR'} ")
    end
  end
end
