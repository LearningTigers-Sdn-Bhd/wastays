# frozen_string_literal: true

module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :safe_guest_attr, :guest_stays_count, :guest_currency_totals

    before_action :set_guest, only: [ :show, :edit, :update, :destroy ]

    def index
      unless current_hotel
        @guests = Guest.none.page(params[:page]).per(25)
        @country_options = []
        @guest_stays_count = {}
        @guest_currency_totals = {}
        return
      end

      query = Guests::GuestQuery.new(hotel: current_hotel, params: params)

      @guests = query.call.page(params[:page]).per(25)
      @country_options = query.country_options

      stats = Guests::StatsService.new(hotel: current_hotel, guest_ids: @guests.map(&:id)).call
      @guest_stays_count = stats[:stays_count]
      @guest_currency_totals = stats[:currency_totals]
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

    def destroy
      result = Guests::DestroyService.new(guest: @guest, hotel: current_hotel).call

      if result.success?
        redirect_to hotel_guests_path(current_hotel), notice: result.message, status: :see_other
      else
        redirect_to hotel_guests_path(current_hotel), alert: result.message, status: :see_other
      end
    end

    def safe_guest_attr(guest, attribute)
      Guests::GuestPresenter.new(guest).public_send(attribute)
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
