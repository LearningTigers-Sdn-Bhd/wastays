# frozen_string_literal: true

# Maps a row of any activity tab to the columns the Activity Log shows.
class ActivityLogRow
  Row = Data.define(:record, :hotel, :time, :who, :event, :details, :summary, :detail)

  def self.for(tab, record) = send("build_#{tab}", record)

  def self.build_inventory(log)
    Row.new(
      record: log, hotel: log.hotel.name, time: log.created_at, who: log.user&.name, event: log.action_type.titleize,
      details: log.display_details, summary: log.display_value_change,
      detail: { old_value: log.old_value, new_value: log.new_value, metadata: log.metadata }
    )
  end

  def self.build_bookings(log)
    Row.new(
      record: log, hotel: log.hotel.name, time: log.occurred_at, who: log.user&.name || log.source.to_s.titleize, event: log.action_label,
      details: log.display_auditable_name, summary: log.display_value_change.truncate(160),
      detail: { category: log.category, source: log.source, old_value: log.old_value, new_value: log.new_value, metadata: log.metadata }
    )
  end

  def self.build_folios(log)
    Row.new(
      record: log, hotel: log.hotel.name, time: log.created_at, who: log.actor&.name || "System", event: log.operation_type.humanize,
      details: log.booking.confirmation_token, summary: log.reason.to_s,
      detail: { reason: log.reason, currency: log.currency, metadata: log.metadata }.compact
    )
  end

  def self.build_night_audits(log)
    Row.new(
      record: log, hotel: log.hotel.name, time: log.created_at, who: log.user&.name || "System", event: log.action_type.humanize,
      details: "Business date #{log.night_audit.business_date}", summary: log.message.to_s,
      detail: { message: log.message, metadata: log.metadata }.compact
    )
  end

  def self.build_onboarding(event)
    Row.new(
      record: event, hotel: event.hotel.name, time: event.occurred_at, who: event.user&.name || "System", event: event.event_type.humanize,
      details: event.section_key&.humanize, summary: "",
      detail: { section_key: event.section_key, metadata: event.metadata }.compact
    )
  end

  def self.build_rooms(log)
    Row.new(
      record: log, hotel: log.hotel.name, time: log.created_at, who: log.user&.name || "System", event: log.event_type.humanize,
      details: "Room #{log.room_number}", summary: room_summary(log),
      detail: { room_number: log.room_number, old_status: log.old_status, new_status: log.new_status, reason: log.reason, metadata: log.metadata }.compact
    )
  end

  def self.build_financial(event)
    Row.new(
      record: event, hotel: event.hotel.name, time: event.occurred_at, who: event.actor.try(:name) || event.source.to_s.titleize, event: event.event_type.humanize,
      details: event.booking&.confirmation_token || "Business date #{event.business_date}", summary: event.reason.to_s,
      detail: { source: event.source, business_date: event.business_date, currency: event.currency, reason: event.reason, metadata: event.metadata }.compact
    )
  end

  def self.build_errors(event)
    Row.new(
      record: event, hotel: nil, time: event.occurred_at, who: nil, event: event.error_class,
      details: event.message.to_s.truncate(160),
      summary: [ event.handled ? "Handled" : "Not handled", event.severity.titleize, event.source ].compact_blank.join(" / "),
      detail: { error_class: event.error_class, message: event.message, severity: event.severity, handled: event.handled,
                source: event.source, context: event.context, backtrace: event.backtrace.to_s.lines.map(&:strip) }
    )
  end

  def self.room_summary(log)
    change = [ log.old_status, log.new_status ].map { |status| status.to_s.humanize.presence || "N/A" }.join(" -> ") if log.old_status || log.new_status
    [ change, log.reason.presence ].compact.join(". ")
  end

  private_class_method :build_inventory, :build_bookings, :build_folios, :build_night_audits,
                       :build_onboarding, :build_rooms, :build_financial, :build_errors, :room_summary
end
