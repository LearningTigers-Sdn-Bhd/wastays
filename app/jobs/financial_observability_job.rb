# frozen_string_literal: true

class FinancialObservabilityJob < ApplicationJob
  queue_as :default

  def perform
    HotelTeamConfig.where(template_type: "financial_observability").find_each do |config|
      next unless alert_due?(config)

      anomalies = FinancialControls::EvaluateAnomalies.call(config.hotel)

      # Only send if there are actual anomalies to report
      if report_worthy?(anomalies)
        FinanceAlertMailer.daily_digest(config, anomalies).deliver_now
        config.update!(last_alert_sent_at: Time.current)
      end
    end
  end

  private

  def alert_due?(config)
    return true if config.last_alert_sent_at.nil?

    Time.current >= config.last_alert_sent_at + config.frequency.seconds
  end

  def report_worthy?(anomalies)
    anomalies[:unbalanced_folios].any? ||
      anomalies[:audit_sync_lags].any? ||
      anomalies[:override_abuse].present?
  end
end
