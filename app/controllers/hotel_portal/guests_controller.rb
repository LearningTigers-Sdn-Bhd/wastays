# frozen_string_literal: true

module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :safe_guest_attr, :guest_stays_count, :guest_currency_totals

    before_action :set_guest, only: [ :show, :edit, :update ]

    def index
      unless current_hotel
        @guests = Guest.none.page(params[:page]).per(25)
        @country_options = []
        @guest_stays_count = {}
        @guest_currency_totals = {}
        return
      end

      @guests = ActiveRecord::Encryption.without_encryption do
        # Guests who have stayed at this hotel OR were registered by this hotel
        scope = Guest
          .select("guests.*, COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp)) AS last_stay_at")
          .left_joins(:bookings)
          .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: current_hotel.id)

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
          .order(Arel.sql("COALESCE(MAX(bookings.checked_out_at), MAX(bookings.check_out::timestamp), guests.created_at) DESC NULLS LAST"))
          .page(params[:page])
          .per(25)
      end

      @country_options = ActiveRecord::Encryption.without_encryption do
        Guest
          .left_joins(:bookings)
          .where("bookings.hotel_id = :hotel_id OR guests.created_by_hotel_id = :hotel_id", hotel_id: current_hotel.id)
          .where.not(country: [ nil, "" ])
          .distinct
          .order(:country)
          .pluck(:country)
      end

      # Totals for guests in the current page
      guest_ids = @guests.map(&:id)

      booking_scope = Booking
        .joins(:booking_guests)
        .where(hotel_id: current_hotel.id, booking_guests: { guest_id: guest_ids })

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

    def new
      @guest = Guest.new(country: current_hotel.country)
    end

    def create
      @guest = Guest.new(guest_params)
      @guest.created_by_hotel = current_hotel

      if @guest.save
        redirect_to hotel_guest_path(current_hotel, @guest), notice: "Guest record created successfully."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @guest.update(guest_params)
        redirect_to hotel_guest_path(current_hotel, @guest), notice: "Guest record updated successfully."
      else
        render :edit, status: :unprocessable_content
      end
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

      # Allow access if they have a booking OR were created by this hotel
      return if @guest.created_by_hotel_id == current_hotel.id
      return if @guest.bookings.where(hotel_id: current_hotel.id).exists?

      raise ActiveRecord::RecordNotFound
    end

    def guest_params
      params.require(:guest).permit(:name, :email, :phone, :country, :gender, :document_type, :government_id)
    end
  end
end
