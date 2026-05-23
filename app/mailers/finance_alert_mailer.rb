class FinanceAlertMailer < ApplicationMailer
  def daily_digest(team_config, anomalies)
    @team_config = team_config
    @anomalies = anomalies
    @hotel = team_config.hotel

    mail(
      to: @team_config.emails,
      subject: "[Finance Alert] Daily Observability Digest - #{@hotel.name}"
    )
  end
end
