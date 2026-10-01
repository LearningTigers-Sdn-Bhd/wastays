# frozen_string_literal: true

# Maps a row of any activity tab to the columns the Activity Log shows.
class ActivityLogRow
  Row = Data.define(:record, :time, :who, :event, :details, :summary, :detail)

  def self.for(tab, record) = send("build_#{tab}", record)

  def self.build_inventory(log)
    Row.new(
      record: log, time: log.created_at, who: log.user&.name, event: log.action_type.titleize,
      details: log.display_details, summary: log.display_value_change,
      detail: { old_value: log.old_value, new_value: log.new_value, metadata: log.metadata }
    )
  end

  def self.build_bookings(log)
    Row.new(
      record: log, time: log.occurred_at, who: log.user&.name || log.source.to_s.titleize, event: log.action_label,
      details: log.display_auditable_name, summary: log.display_value_change.truncate(160),
      detail: { category: log.category, source: log.source, old_value: log.old_value, new_value: log.new_value, metadata: log.metadata }
    )
  end

  def self.build_folios(log)
    Row.new(
      record: log, time: log.created_at, who: log.actor&.name || "System", event: log.operation_type.humanize,
      details: log.booking.confirmation_token, summary: log.reason.to_s,
      detail: { reason: log.reason, currency: log.currency, metadata: log.metadata }.compact
    )
  end

  private_class_method :build_inventory, :build_bookings, :build_folios
end
