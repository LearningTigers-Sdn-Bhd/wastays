# frozen_string_literal: true

module FolioInvoicePackages
  class RecipientResolver
    Recipient = Data.define(:key, :kind, :name, :email)

    def self.call(invoice)
      new(invoice).call
    end

    def initialize(invoice)
      @folio = invoice.booking_folio
      @booking = @folio.booking
    end

    def call
      @folio.payer_type == "company" ? company_recipient : guest_recipient
    end

    private

    def company_recipient
      relationship = @folio.hotel_corporate_account || @folio.booking_billing_party&.hotel_corporate_account
      account = relationship&.corporate_account
      email = relationship&.contact_email.presence || account&.users&.min_by(&:id)&.email.presence

      Recipient.new(
        key: "company:#{relationship&.id || @folio.id}",
        kind: "company",
        name: account&.name.presence || @folio.booking_billing_party&.display_name.presence || "Corporate payer",
        email:
      )
    end

    def guest_recipient
      booking_guest = @folio.booking_billing_party&.booking_guest || @booking.booking_guests.find(&:is_primary?)
      email = booking_guest&.email_snapshot.presence || booking_guest&.guest&.email.presence || @booking.guest_email.presence
      name = booking_guest&.name_snapshot.presence || booking_guest&.guest&.name.presence || @booking.guest_name.presence || "Guest"
      identity = booking_guest&.guest_id || booking_guest&.id || email&.downcase || @booking.id

      Recipient.new(key: "guest:#{identity}", kind: "guest", name:, email:)
    end
  end
end
