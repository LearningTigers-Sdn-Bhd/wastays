# frozen_string_literal: true

module MailEvents
  # Writes one MailEvent for each email that ActionMailer delivers.
  # It never raises, so a logging problem cannot block an email.
  class Record
    def self.call(...) = new(...).call

    def initialize(payload:, finished_at: Time.current)
      @payload = payload
      @finished_at = finished_at
    end

    def call
      MailEvent.create!(
        mailer: @payload[:mailer].to_s,
        mail_action: @payload[:action].to_s.presence,
        subject: @payload[:subject].to_s.truncate(255),
        recipients: recipients,
        status: error ? "failed" : "sent",
        error_message: error&.message&.truncate(1_000),
        sent_at: @finished_at
      )
    rescue StandardError => e
      Rails.logger.error("[MailEvents::Record] #{e.class}: #{e.message}")
      nil
    end

    private

    def error = @payload[:exception_object]

    def recipients
      %i[to cc bcc].flat_map { |field| Array(@payload[field]) }.compact_blank.uniq.join(", ").presence
    end
  end
end
