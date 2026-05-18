class NightAuditFinancialSummary < ApplicationRecord
  belongs_to :night_audit

  validates :room_revenue, :tax_revenue, :payments_total, :refunds_total, :no_show_penalties, presence: true, numericality: true

  def log_change(user:, previous_values:, new_values:, reason:)
    current_changelog = Array(changelog).dup
    current_changelog << {
      timestamp: Time.current,
      user_id: user&.id,
      user_name: user&.name,
      reason: reason,
      previous_values: previous_values,
      new_values: new_values
    }
    self.changelog = current_changelog
  end
end
