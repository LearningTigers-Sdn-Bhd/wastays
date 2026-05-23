# Preview all emails at http://localhost:3000/rails/mailers/finance_alert_mailer
class FinanceAlertMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/finance_alert_mailer/daily_digest
  def daily_digest
    FinanceAlertMailer.daily_digest
  end
end
