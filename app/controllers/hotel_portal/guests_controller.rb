module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :safe_guest_attr, :guest_stays_count, :guest_currency_totals

    before_action :set_guest, only: [ :show ]

    def index
      unless current_hotel
        @guests = Guest.none.page(params[:page]).per(25)
        @country_options = []
        @guest_stays_count = {}
        @guest_currency_totals = {}
        return
      end

      @guests = ActiveRecord::Encryption.without_encryption do
        scope = Guest
          .select("guests.*, COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp)) AS last_stay_at")
          .joins(:bookings)
          .where(bookings: { hotel_id: current_hotel.id })
        if params[:query].present?
          query = "%#{params[:query].to_s.downcase.strip}%"
          scope = scope.where(
            "LOWER(guests.name) LIKE :query OR LOWER(guests.email) LIKE :query OR guests.phone LIKE :query",
            query: query
          )
        end

        scope = scope.where(country: params[:country]) if params[:country].present?

        scope
          .group("guests.id")
          .order(Arel.sql("COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp)) DESC NULLS LAST"))
          .page(params[:page])
          .per(25)
      end

      @country_options = ActiveRecord::Encryption.without_encryption do
        Guest
          .joins(:bookings)
          .where(bookings: { hotel_id: current_hotel.id })
          .where.not(country: [ nil, "" ])
          .distinct
          .order(:country)
          .pluck(:country)
      end

      booking_scope = Booking
        .joins(:booking_guests)
        .where(hotel_id: current_hotel.id, booking_guests: { guest_id: @guests.map(&:id) })

      @guest_stays_count = booking_scope
        .group("booking_guests.guest_id")
        .distinct
        .count("bookings.id")

      @guest_currency_totals = booking_scope
        .group("booking_guests.guest_id", :currency)
        .sum(:total_amount)
        .each_with_object({}) do |((guest_id, currency), amount), totals|
          totals[guest_id] ||= {}
          totals[guest_id][currency] = amount
        end
    end

    def show
      guest_booking_scope = Booking
        .joins(:booking_guests)
        .where(hotel_id: current_hotel.id, booking_guests: { guest_id: @guest.id })

      @all_bookings = guest_booking_scope
        .includes(:pre_checkin)
        .order(check_out: :desc, id: :desc)
      @bookings = @all_bookings.page(params[:page]).per(25)

      @currency_totals = guest_booking_scope
        .reorder(nil)
        .group(:currency)
        .sum(:total_amount)
    end

    def safe_guest_attr(guest, attribute)
      guest.public_send(attribute)
    rescue ActiveRecord::Encryption::Errors::Decryption
      "Encrypted data"
    end

    def guest_stays_count(guest)
      @guest_stays_count.fetch(guest.id, 0)
    end

    def guest_currency_totals(guest)
      @guest_currency_totals.fetch(guest.id, {})
    end

    private

    def set_guest
      @guest = ActiveRecord::Encryption.without_encryption { Guest.find(params[:id]) }
      return if @guest.bookings.where(hotel_id: current_hotel.id).exists?

      raise ActiveRecord::RecordNotFound
    end
  end
end
