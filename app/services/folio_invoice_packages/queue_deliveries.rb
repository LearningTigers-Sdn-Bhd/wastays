# frozen_string_literal: true

module FolioInvoicePackages
  class QueueDeliveries
    Result = Data.define(:deliveries, :groups)

    def self.call(hotel:, bookings:, anchor_booking:, source:, requested_by: nil)
      new(hotel:, bookings:, anchor_booking:, source:, requested_by:).call
    end

    def initialize(hotel:, bookings:, anchor_booking:, source:, requested_by:)
      @hotel = hotel
      @bookings = Array(bookings)
      @anchor_booking = anchor_booking
      @source = source.to_s
      @requested_by = requested_by
    end

    def call
      invoices = Collect.call(hotel: @hotel, bookings: @bookings)
      groups = GroupByPayer.call(invoices:)
      deliveries = groups.map { |group| create_delivery(group) }
      Result.new(deliveries:, groups:)
    end

    private

    def create_delivery(group)
      invoice_ids = group.invoices.map(&:id).sort
      revision_ids = invoice_ids.map { |id| group.invoices.find { |invoice| invoice.id == id }.current_revision.id }
      recipient = group.recipient
      skipped = recipient.email.blank?
      delivery = NotificationDelivery.find_or_initialize_by(
        idempotency_key: idempotency_key(recipient.key, invoice_ids, revision_ids)
      )
      return delivery if delivery.persisted?

      delivery.assign_attributes(
        hotel: @hotel,
        booking: @anchor_booking,
        notification_type: "invoice_package",
        channel: "email",
        trigger_event: @source,
        status: skipped ? "skipped" : "pending",
        error_message: ("No saved email is available for #{recipient.name}." if skipped),
        payload: {
          folio_invoice_ids: invoice_ids,
          folio_invoice_revision_ids: revision_ids,
          payer_key: recipient.key,
          payer_kind: recipient.kind,
          payer_name: recipient.name,
          recipient_email: recipient.email,
          invoice_count: invoice_ids.size,
          hotel_name: @hotel.name,
          source: @source,
          requested_by_id: @requested_by&.id,
          requested_by_name: @requested_by&.name
        }
      )
      delivery.save!
      Notifications::DeliverJob.perform_later(delivery.id) unless skipped
      delivery
    end

    def idempotency_key(payer_key, invoice_ids, revision_ids)
      base = [ @hotel.id, "invoice_package", @source, payer_key, invoice_ids.join("-"), revision_ids.join("-") ]
      base << SecureRandom.hex(8) if @source == "manual_resend"
      base.join(":")
    end
  end
end
