class ApplicationMailer < ActionMailer::Base
  default from: -> {
    mailer_from = Rails.application.config.x.mailer_from
    mailer_from = nil unless mailer_from.is_a?(String)
    mailer_from.presence || "WAStays <noreply@updates.wastays.com>"
  }
  layout "mailer"
end
