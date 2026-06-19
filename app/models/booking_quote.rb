class BookingQuote < ApplicationRecord
  belongs_to :hotel
  has_many :booking_quote_items, dependent: :destroy

  validates :check_in, :check_out, :adults, :total_amount, :expires_at, :token, presence: true
  validates :token, uniqueness: true
  validates :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :display_currency, inclusion: { in: ->(_) { CurrencyCatalog.codes }, allow_blank: true }

  before_validation :generate_token, on: :create
  before_validation :normalize_currencies

  def stay_restriction_error_message
    nights = (check_out - check_in).to_i

    booking_quote_items.each do |item|
      # 1. Check snapshot values safely
      if item.nightly_rate_snapshot.present?
        item.nightly_rate_snapshot.each do |date_str, rate_data|
          next unless rate_data.is_a?(Hash)

          min_stay = rate_data["min_stay"]
          max_stay = rate_data["max_stay"]

          if min_stay.present? && nights < min_stay.to_i
            return "The stay duration does not follow the minimum stay requirement of #{min_stay} night(s) for this rate."
          end
          if max_stay.present? && nights > max_stay.to_i
            return "The stay duration does not follow the maximum stay requirement of #{max_stay} night(s) for this rate."
          end
        end
      end

      # 2. Check current database values in case restrictions were updated/added
      rate_plan_ids = [nil]
      if item.nightly_rate_snapshot.present?
        item.nightly_rate_snapshot.values.each do |rate_data|
          if rate_data.is_a?(Hash) && rate_data["rate_plan_id"].present?
            rate_plan_ids << rate_data["rate_plan_id"]
          end
        end
      end

      # If checking base rate plan (nil), also include standard rate plan of the room type.
      if rate_plan_ids.include?(nil)
        standard_plan = item.room_type&.rate_plans&.first
        rate_plan_ids << standard_plan.id if standard_plan
      end

      rate_plan_ids.uniq!

      room_rates = RoomRate.where(
        room_type_id: item.room_type_id,
        date: check_in...check_out,
        rate_plan_id: rate_plan_ids
      )

      room_rates.each do |rate|
        if rate.min_stay.present? && nights < rate.min_stay
          return "The stay duration does not follow the minimum stay requirement of #{rate.min_stay} night(s) for this stay."
        end
        if rate.max_stay.present? && nights > rate.max_stay
          return "The stay duration does not follow the maximum stay requirement of #{rate.max_stay} night(s) for this stay."
        end
      end
    end

    nil
  end

  def stay_restriction_violated?
    stay_restriction_error_message.present?
  end

  private

  def normalize_currencies
    self.currency = CurrencyCatalog.normalize(currency)
    self.display_currency = CurrencyCatalog.normalize(display_currency, fallback: nil) if display_currency.present?
  end

  def generate_token
    self.token ||= SecureRandom.hex(16)
  end
end
