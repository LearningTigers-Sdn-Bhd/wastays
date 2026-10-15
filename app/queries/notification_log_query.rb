# frozen_string_literal: true

# One tab of the admin Notification Log. Each tab reads one table, so paging stays exact.
class NotificationLogQuery
  TABS = %w[whatsapp staff].freeze

  def self.tab(params) = TABS.include?(params[:tab]) ? params[:tab] : TABS.first

  def initialize(params = {})
    @params = params
  end

  def tab = self.class.tab(@params)

  def call
    tab == "staff" ? staff_alerts : whatsapp_messages
  end

  private

  def whatsapp_messages
    rows = NotificationDelivery.where(channel: "whatsapp").joins(:booking).includes(:hotel, :booking)
    rows = rows.where("notification_deliveries.notification_type ILIKE :q OR bookings.confirmation_token ILIKE :q OR bookings.guest_name ILIKE :q", q: like) if search.present?
    in_range(rows, "notification_deliveries.created_at").order(created_at: :desc, id: :desc)
  end

  def staff_alerts
    rows = StaffNotification.joins(:recipient).includes(:hotel, :recipient)
    rows = rows.where("staff_notifications.title ILIKE :q OR staff_notifications.message ILIKE :q OR users.name ILIKE :q", q: like) if search.present?
    in_range(rows, "staff_notifications.created_at").recent
  end

  def in_range(rows, column)
    range = LogDateRange.call(@params[:range])
    range ? rows.where(column => range) : rows
  end

  def search = @search ||= @params[:q].to_s.strip

  def like = "%#{ApplicationRecord.sanitize_sql_like(search)}%"
end
