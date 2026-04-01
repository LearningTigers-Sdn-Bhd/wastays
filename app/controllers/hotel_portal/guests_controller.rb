module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :safe_guest_attr

    before_action :set_guest, only: [ :show ]

    def index
      return @guests = [] unless current_hotel

      @guests = ActiveRecord::Encryption.without_encryption do
        Guest
          .select("guests.*, MAX(bookings.check_out) AS last_stay_at")
          .joins(:bookings)
          .where(bookings: { hotel_id: current_hotel.id })
          .group("guests.id")
          .order(Arel.sql("MAX(bookings.check_out) DESC NULLS LAST"))
      end
    end

    def show
      @bookings = @guest.bookings.where(hotel_id: current_hotel.id).order(check_out: :desc)
      @currency_totals = @bookings.group(:currency).sum(:total_amount)
    end

    def safe_guest_attr(guest, attribute)
      guest.public_send(attribute)
    rescue ActiveRecord::Encryption::Errors::Decryption
      "Encrypted data"
    end

    private

    def set_guest
      @guest = ActiveRecord::Encryption.without_encryption { Guest.find(params[:id]) }
      return if @guest.bookings.where(hotel_id: current_hotel.id).exists?

      raise ActiveRecord::RecordNotFound
    end

    private

    def set_guest
      @guest = ActiveRecord::Encryption.without_encryption { Guest.find(params[:id]) }
      return if @guest.bookings.where(hotel_id: current_hotel.id).exists?

      raise ActiveRecord::RecordNotFound
    end
  end
end
