module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :safe_guest_attr

    def index
      if current_hotel
        @guests = ActiveRecord::Encryption.without_encryption do
          Guest.joins(:bookings).where(bookings: { hotel_id: current_hotel.id }).distinct
        end
      else
        @guests = []
      end
    end

    def safe_guest_attr(guest, attribute)
      guest.public_send(attribute)
    rescue ActiveRecord::Encryption::Errors::Decryption
      "Encrypted data"
    end
  end
end
