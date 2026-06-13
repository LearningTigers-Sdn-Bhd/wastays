# frozen_string_literal: true

module HotelOps
  class BuildNightAuditRunResults
    def self.call(night_audit:)
      new(night_audit: night_audit).call
    end

    def initialize(night_audit:)
      @night_audit = night_audit
    end

    def call
      {
        "status_changes" => summarized(status_changes),
        "charges_posted" => summarized(charges_posted, total: charges_posted.sum { |item| item["amount"].to_d }),
        "skipped_items" => summarized(logged_items("item_skipped")),
        "failed_items" => summarized(failed_items)
      }
    end

    private

    def status_changes
      BookingAuditLog.where(hotel: @night_audit.hotel, auditable_type: "Booking", source: "night_audit")
        .where("metadata->>'night_audit_id' = ?", @night_audit.id.to_s)
        .order(:id)
        .map do |log|
          booking = log.auditable
          {
            "item_key" => "booking_audit_log:#{log.id}",
            "booking_id" => log.auditable_id,
            "confirmation_token" => booking.confirmation_token,
            "guest_name" => booking.guest_name,
            "from" => log.old_value["status"],
            "to" => log.new_value["status"],
            "occurred_at" => log.occurred_at&.iso8601
          }
        end
    end

    def charges_posted
      FolioTransaction.joins(booking_folio: :booking)
        .where(bookings: { hotel_id: @night_audit.hotel_id })
        .where("folio_transactions.metadata->>'night_audit_id' = ?", @night_audit.id.to_s)
        .order(:id)
        .map do |transaction|
          {
            "item_key" => "folio_transaction:#{transaction.id}",
            "folio_transaction_id" => transaction.id,
            "booking_id" => transaction.metadata["booking_id"] || transaction.booking_folio.booking_id,
            "category" => transaction.category,
            "amount" => transaction.amount.to_s,
            "posting_date" => transaction.posting_date.iso8601
          }
        end
    end

    def logged_items(action_type)
      @night_audit.night_audit_logs.where(action_type: action_type).order(:id).filter_map do |log|
        item = log.metadata["item"]
        item if item.is_a?(Hash)
      end
    end

    def failed_items
      items = logged_items("item_failed")
      items + @night_audit.night_audit_logs.where(action_type: "failed").order(:id).filter_map do |log|
        error = log.metadata["error"].presence
        next unless error

        {
          "item_key" => "audit_failure:#{error}",
          "item_type" => "night_audit",
          "reason" => error
        }
      end
    end

    def summarized(items, total: nil)
      unique_items = items.reverse.uniq { |item| item["item_key"] }.reverse
      result = { "count" => unique_items.count, "items" => unique_items }
      result["total"] = total.to_d.to_s if total
      result
    end
  end
end
