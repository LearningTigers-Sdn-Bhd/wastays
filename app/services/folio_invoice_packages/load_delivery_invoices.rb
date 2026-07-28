# frozen_string_literal: true

module FolioInvoicePackages
  class LoadDeliveryInvoices
    def self.call(delivery:)
      new(delivery:).call
    end

    def initialize(delivery:)
      @delivery = delivery
      @payload = delivery.payload.to_h.with_indifferent_access
    end

    def call
      ids = Array(@payload[:folio_invoice_ids]).map(&:to_i)
      revision_ids = Array(@payload[:folio_invoice_revision_ids]).map(&:to_i)
      invoices = @delivery.hotel.folio_invoices
        .where(id: ids)
        .includes(
          :revisions,
          booking_folio: [
            :ar_invoice,
            :booking_room,
            { booking: { booking_rooms: :room_type } },
            { folio_transactions: [ :transaction_code, :user ] },
            { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: { corporate_account: :users } } ] },
            { hotel_corporate_account: { corporate_account: :users } }
          ]
        )
        .index_by(&:id)
      ordered = ids.filter_map { |id| invoices[id] }
      raise UnavailableError, "One or more invoices no longer belong to this hotel." unless ordered.size == ids.size

      ordered.each_with_index do |invoice, index|
        folio = invoice.booking_folio
        recipient = RecipientResolver.call(invoice)
        valid = invoice.finalized? && folio.closed? && folio.ar_invoice.blank? &&
          invoice.current_revision&.id == revision_ids[index] &&
          recipient.key == @payload[:payer_key] &&
          recipient.email.present? && recipient.email == @payload[:recipient_email]
        raise UnavailableError, "Invoice #{invoice.invoice_reference} is no longer available to send." unless valid
      end
      ordered
    end
  end
end
