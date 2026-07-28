# frozen_string_literal: true

module Notifications
  class InvoiceDelivery
    UnavailableError = Class.new(StandardError)
    Recipient = Data.define(:key, :kind, :name, :email)
    Group = Data.define(:recipient, :invoices)
    QueueResult = Data.define(:deliveries, :groups)

    Preview = Data.define(:groups) do
      def valid_groups = groups.select { |group| group.recipient.email.present? }
      def skipped_groups = groups.reject { |group| group.recipient.email.present? }
      def invoice_count = groups.sum { |group| group.invoices.size }
      def resendable? = valid_groups.any?

      def tooltip
        return "No finalized invoices are available to resend." if groups.empty?
        return "Cannot resend—this payer has no saved email." if valid_groups.empty?

        if groups.one?
          group = groups.first
          count = group.invoices.size
          "Resend #{count} finalized #{'invoice'.pluralize(count)} to #{group.recipient.email}."
        else
          "Send separate invoice emails to #{valid_groups.size} saved payer contacts."
        end
      end
    end

    def self.preview(hotel:, bookings:)
      service = new(hotel:, bookings:)
      Preview.new(groups: service.send(:groups))
    end

    def self.queue(hotel:, bookings:, anchor_booking:, source:, requested_by: nil)
      new(hotel:, bookings:, anchor_booking:, source:, requested_by:).send(:queue)
    end

    def self.load!(delivery:)
      new(hotel: delivery.hotel, delivery:).send(:load!)
    end

    private_class_method :new

    def initialize(hotel:, bookings: [], anchor_booking: nil, source: nil, requested_by: nil, delivery: nil)
      @hotel = hotel
      @booking_ids = Array(bookings).map { |booking| booking.respond_to?(:id) ? booking.id : booking }.compact.uniq
      @anchor_booking = anchor_booking
      @source = source.to_s
      @requested_by = requested_by
      @delivery = delivery
    end

    private

    def groups
      @groups ||= collect_invoices.group_by { |invoice| recipient_for(invoice).key }.values.map do |invoices|
        Group.new(recipient: recipient_for(invoices.first), invoices:)
      end
    end

    def queue
      deliveries = groups.map { |group| create_delivery(group) }
      QueueResult.new(deliveries:, groups:)
    end

    def load!
      payload = @delivery.payload.to_h.with_indifferent_access
      ids = Array(payload[:folio_invoice_ids]).map(&:to_i)
      revision_ids = Array(payload[:folio_invoice_revision_ids]).map(&:to_i)
      raise UnavailableError, "Delivery has no invoices." if ids.empty?

      invoices = delivery_scope.where(id: ids).index_by(&:id)
      ordered = ids.filter_map { |id| invoices[id] }
      raise UnavailableError, "One or more invoices no longer belong to this hotel." unless ordered.size == ids.size

      ordered.each_with_index do |invoice, index|
        folio = invoice.booking_folio
        recipient = recipient_for(invoice)
        valid = invoice.finalized? && folio.closed? && folio.ar_invoice.blank? &&
          invoice.current_revision&.id == revision_ids[index] &&
          recipient.key == payload[:payer_key] &&
          recipient.email.present? && recipient.email == payload[:recipient_email]
        raise UnavailableError, "Invoice #{invoice.invoice_reference} is no longer available to send." unless valid
      end

      Group.new(recipient: recipient_for(ordered.first), invoices: ordered)
    end

    def collect_invoices
      return [] if @booking_ids.empty?

      delivery_scope
        .joins(:booking_folio)
        .where(state: "finalized", booking_folios: { booking_id: @booking_ids, status: "closed" })
        .order("booking_folios.booking_id", "booking_folios.folio_sequence", :id)
        .select { |invoice| invoice.current_revision.present? && invoice.booking_folio.ar_invoice.blank? }
    end

    def delivery_scope
      @hotel.folio_invoices.includes(
        :revisions,
        booking_folio: [
          :ar_invoice,
          :booking_room,
          { booking: [ { booking_rooms: :room_type }, { booking_guests: :guest } ] },
          { folio_transactions: [ :transaction_code, :user ] },
          { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: { corporate_account: :users } } ] },
          { hotel_corporate_account: { corporate_account: :users } }
        ]
      )
    end

    def recipient_for(invoice)
      folio = invoice.booking_folio
      booking = folio.booking
      return company_recipient(folio) if folio.payer_type == "company"

      booking_guest = folio.booking_billing_party&.booking_guest || booking.booking_guests.find(&:is_primary?)
      email = booking_guest&.email_snapshot.presence || booking_guest&.guest&.email.presence || booking.guest_email.presence
      name = booking_guest&.name_snapshot.presence || booking_guest&.guest&.name.presence || booking.guest_name.presence || "Guest"
      identity = booking_guest&.guest_id || booking_guest&.id || email&.downcase || booking.id
      Recipient.new(key: "guest:#{identity}", kind: "guest", name:, email:)
    end

    def company_recipient(folio)
      relationship = folio.hotel_corporate_account || folio.booking_billing_party&.hotel_corporate_account
      account = relationship&.corporate_account
      email = relationship&.contact_email.presence || account&.users&.min_by(&:id)&.email.presence
      Recipient.new(
        key: "company:#{relationship&.id || folio.id}",
        kind: "company",
        name: account&.name.presence || folio.booking_billing_party&.display_name.presence || "Corporate payer",
        email:
      )
    end

    def create_delivery(group)
      invoice_ids = group.invoices.map(&:id).sort
      invoices_by_id = group.invoices.index_by(&:id)
      revision_ids = invoice_ids.map { |id| invoices_by_id.fetch(id).current_revision.id }
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
      DeliverJob.perform_later(delivery.id) unless skipped
      delivery
    end

    def idempotency_key(payer_key, invoice_ids, revision_ids)
      parts = [ @hotel.id, "invoice_package", @source, payer_key, invoice_ids.join("-"), revision_ids.join("-") ]
      parts << SecureRandom.hex(8) if @source == "manual_resend"
      parts.join(":")
    end
  end
end
