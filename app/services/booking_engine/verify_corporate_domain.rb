# frozen_string_literal: true

module BookingEngine
  class VerifyCorporateDomain
    def initialize(quote:, email:)
      @quote = quote
      @email = email.to_s.strip.downcase
    end

    def call
      return { valid: true } if @quote.partner.blank? || @quote.partner.domain.blank?

      email_domain = @email.split("@").last
      if email_domain == @quote.partner.domain
        { valid: true, message: "✓ Work email verified for #{@quote.partner.name}." }
      else
        {
          valid: false,
          message: "This corporate rate is only valid for @#{@quote.partner.domain} email addresses. Please use your work email."
        }
      end
    end
  end
end
