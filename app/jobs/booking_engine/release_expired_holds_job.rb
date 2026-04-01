module BookingEngine
  class ReleaseExpiredHoldsJob < ApplicationJob
    queue_as :default

    def perform
      expired_quotes = BookingQuote.where(status: "pending").where("expires_at < ?", Time.current)

      expired_quotes.find_each do |quote|
        release_hold(quote)
      end
    end

    private

    def release_hold(quote)
      ActiveRecord::Base.transaction do
        quote.booking_quote_items.each do |item|
          room_type = item.room_type
          quantity = item.quantity
          stay_dates = (quote.check_in...quote.check_out).to_a

          stay_dates.each do |date|
            inventory = room_type.room_inventories.find_by(date: date)
            if inventory
              inventory.update!(quantity: inventory.quantity + quantity)
            end
          end
        end

        quote.update!(status: "expired")
      end
    rescue => e
      Rails.logger.error "Failed to release hold for Quote #{quote.id}: #{e.message}"
    end
  end
end
