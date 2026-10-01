# frozen_string_literal: true

# One tab of the admin Activity Log. Each tab reads one audit table, so paging stays exact.
class ActivityLogQuery
  ACTIVE_WINDOW = 15.minutes

  TABS = {
    "inventory" => { model: InventoryAuditLog, time: :created_at },
    "bookings" => { model: BookingAuditLog, time: :occurred_at },
    "folios" => { model: FolioOperationLog, time: :created_at },
    "night_audits" => { model: NightAuditLog, time: :created_at },
    "onboarding" => { model: OnboardingAuditEvent, time: :occurred_at },
    "rooms" => { model: RoomOperationalAuditLog, time: :created_at },
    "financial" => { model: FinancialAuditEvent, time: :occurred_at },
    "errors" => { model: ErrorEvent, time: :occurred_at, hotel: false },
    "active" => { model: User, time: :last_seen_at, hotel: false, range: false }
  }.freeze

  def self.tab(params) = TABS.key?(params[:tab]) ? params[:tab] : TABS.keys.first
  def self.model(tab) = TABS.fetch(tab).fetch(:model)
  # An error belongs to no hotel, so the hotel filter does not apply to it.
  def self.hotel_scoped?(tab) = TABS.fetch(tab).fetch(:hotel, true)
  # The active tab shows who is online now, so a date range does not apply to it.
  def self.date_filtered?(tab) = TABS.fetch(tab).fetch(:range, true)

  def initialize(params = {})
    @params = params
  end

  def tab = self.class.tab(@params)

  def call
    rows = with_search(INCLUDES.fetch(tab).then { |names| names.empty? ? model.all : model.includes(*names) })
    rows = rows.where(hotel_id: @params[:hotel_id]) if @params[:hotel_id].present? && self.class.hotel_scoped?(tab)
    rows = rows.where(last_seen_at: ACTIVE_WINDOW.ago..) if tab == "active"
    range = LogDateRange.call(@params[:range]) if self.class.date_filtered?(tab)
    rows = rows.where(time_name => range) if range
    rows.reorder(time_column.desc, model.arel_table[:id].desc)
  end

  private

  INCLUDES = {
    "inventory" => %i[hotel room_type user],
    "bookings" => %i[hotel user auditable],
    "folios" => %i[hotel booking actor],
    "night_audits" => %i[hotel night_audit user],
    "onboarding" => %i[hotel user],
    "rooms" => %i[hotel user],
    "financial" => %i[hotel actor booking],
    "errors" => [],
    "active" => %i[hotels]
  }.freeze

  def model = self.class.model(tab)

  def time_name = TABS.fetch(tab).fetch(:time)

  def time_column = model.arel_table[time_name]

  def with_search(rows)
    return rows if search.blank?

    case tab
    when "inventory"
      rows.joins(:user).left_joins(:room_type)
          .where("inventory_audit_logs.action_type ILIKE :q OR users.name ILIKE :q OR room_types.name ILIKE :q", q: like)
    when "bookings"
      rows.left_joins(:user)
          .where("booking_audit_logs.action_type ILIKE :q OR booking_audit_logs.category ILIKE :q OR users.name ILIKE :q", q: like)
    when "folios"
      rows.joins(:booking).left_joins(:actor)
          .where("folio_operation_logs.operation_type ILIKE :q OR folio_operation_logs.reason ILIKE :q OR bookings.confirmation_token ILIKE :q OR users.name ILIKE :q", q: like)
    when "night_audits"
      rows.left_joins(:user)
          .where("night_audit_logs.action_type ILIKE :q OR night_audit_logs.message ILIKE :q OR users.name ILIKE :q", q: like)
    when "onboarding"
      rows.left_joins(:user)
          .where("onboarding_audit_events.event_type ILIKE :q OR onboarding_audit_events.section_key ILIKE :q OR users.name ILIKE :q", q: like)
    when "rooms"
      rows.left_joins(:user)
          .where("room_operational_audit_logs.event_type ILIKE :q OR room_operational_audit_logs.room_number ILIKE :q OR room_operational_audit_logs.reason ILIKE :q OR users.name ILIKE :q", q: like)
    when "active"
      rows.where("users.name ILIKE :q OR users.email ILIKE :q OR users.role ILIKE :q", q: like)
    when "errors"
      rows.where("error_events.error_class ILIKE :q OR error_events.message ILIKE :q", q: like)
    else
      rows.left_joins(:booking)
          .where("financial_audit_events.event_type ILIKE :q OR financial_audit_events.reason ILIKE :q OR financial_audit_events.source ILIKE :q OR bookings.confirmation_token ILIKE :q", q: like)
    end
  end

  def search = @search ||= @params[:q].to_s.strip

  def like = "%#{ApplicationRecord.sanitize_sql_like(search)}%"
end
