# frozen_string_literal: true

module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :guest_stays_count, :guest_currency_totals

    TAB_ACTIONS = %i[details booking_history].freeze
    STATUS_ACTIONS = %i[vip unvip blacklist unblacklist].freeze

    before_action -> { require_feature!("unified_guest_profile") }
    before_action :authorize_view_guest_records!, only: [ :index, :show, *TAB_ACTIONS ]
    before_action :authorize_manage_bookings!, only: [ :search, :check_banned, :new, :create, :edit, :update, *STATUS_ACTIONS ]
    before_action :authorize_delete_guest_record!, only: %i[destroy bulk_destroy]
    before_action :set_guest, only: [ :show, :edit, :update, :destroy, *TAB_ACTIONS, *STATUS_ACTIONS ]
    before_action :set_breadcrumbs, only: [ :new, :create, :edit, :update, *TAB_ACTIONS ]

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

    def search
      @guests = Guests::GuestQuery.new(hotel: current_hotel, params: { query: params[:q] }).call.limit(10)
      results = @guests.map do |guest|
        contact = [ guest.email, guest.phone ].compact_blank.join(" · ")
        {
          value: guest.id,
          label: guest.name,
          description: contact,
          data: {
            name: guest.name,
            email: guest.email,
            phone: guest.phone,
            city: guest.city,
            state_code: guest.state_code,
            postal_code: guest.postal_code,
            address_country: guest.address_country,
            country: guest.country,
            gender: guest.gender,
            date_of_birth: guest.date_of_birth&.iso8601,
            home_address: guest.home_address,
            blacklisted: guest.blacklisted_at?(current_hotel)
          }
        }
      end
      render json: { results: results }
    end

    def check_banned
      is_banned = Guest.banned?(
        email: params[:email],
        phone: params[:phone],
        name: params[:name],
        hotel: current_hotel
      )

      render json: { banned: is_banned }
    end

    # The record page is two tabs, each with its own action, so opening the
    # details never runs the booking history queries.
    def show
      redirect_to details_hotel_guest_path(current_hotel, @guest)
    end

    def details
      @presenter = Guests::GuestPresenter.new(@guest)
      query = bookings_query
      @stays_count = query.stays_count
      @last_checkout_on = query.last_checkout_on
    end

    def booking_history
      @presenter = Guests::GuestPresenter.new(@guest)
      query = bookings_query
      @stays_count = query.stays_count
      @bookings = query.bookings(page: params[:page])
      @currency_totals = query.currency_totals
    end

    def new
      @guest = Guest.new(city: current_hotel.city, country: current_hotel.country)
    end

    def create
      @guest = Guest.new(guest_params)
      @guest.created_by_hotel = current_hotel

      if @guest.save
        redirect_to details_hotel_guest_path(current_hotel, @guest), notice: "Guest record created successfully."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @guest.update(guest_params)
        redirect_to details_hotel_guest_path(current_hotel, @guest), notice: "Guest record updated successfully."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # Explicit actions rather than one toggle. A toggle reads the current state
    # on the server, so a stale page flips the wrong way, and it has no sensible
    # meaning across a mixed bulk selection.
    def vip
      set_vip(true)
    end

    def unvip
      set_vip(false)
    end

    def blacklist
      set_blacklisted(true, reason: params[:blacklist_reason])
    end

    def unblacklist
      set_blacklisted(false)
    end

    def destroy
      result = Guests::DestroyService.new(guest: @guest, hotel: current_hotel).call

      if result.success?
        redirect_to hotel_guests_path(current_hotel), notice: result.message, status: :see_other
      else
        redirect_to hotel_guests_path(current_hotel), alert: result.message, status: :see_other
      end
    end

    def bulk_destroy
      guest_ids = begin
        JSON.parse(params[:guest_ids] || "[]")
      rescue JSON::ParserError
        []
      end

      result = Guests::BulkDestroyService.new(guest_ids: guest_ids, hotel: current_hotel).call

      if result.success?
        redirect_to hotel_guests_path(current_hotel), notice: result.message, status: :see_other
      else
        redirect_to hotel_guests_path(current_hotel), alert: result.message, status: :see_other
      end
    end



    def guest_stays_count(guest)
      @guest_stays_count.fetch(guest.id, 0)
    end

    def guest_currency_totals(guest)
      @guest_currency_totals.fetch(guest.id, {})
    end

    private

    def bookings_query
      Guests::GuestBookingsQuery.new(hotel: current_hotel, guest: @guest)
    end

    def set_vip(value)
      result = Guests::SetVip.new(guests: @guest, hotel: current_hotel, vip: value).call
      redirect_after_status_change(result)
    end

    def set_blacklisted(value, reason: nil)
      result = Guests::SetBlacklist.new(
        guests: @guest,
        hotel: current_hotel,
        blacklisted: value,
        actor: current_user,
        reason: reason
      ).call
      redirect_after_status_change(result)
    end

    def redirect_after_status_change(result)
      destination = details_hotel_guest_path(current_hotel, @guest)

      if result.success?
        redirect_to destination, notice: result.message
      else
        redirect_to destination, alert: result.message
      end
    end

    def set_guest
      @guest = ActiveRecord::Encryption.without_encryption { Guest.kept.find(params[:id]) }

      # Allow access if they have a booking OR were created by this hotel
      return if @guest.created_by_hotel_id == current_hotel.id
      return if @guest.bookings.where(hotel_id: current_hotel.id).exists?

      raise ActiveRecord::RecordNotFound
    end

    def set_breadcrumbs
      if @guest&.persisted?
        presenter = Guests::GuestPresenter.new(@guest)
        append_breadcrumb presenter.name, details_hotel_guest_path(current_hotel, @guest)
        append_breadcrumb "Edit" if action_name.in?([ "edit", "update" ])
        append_breadcrumb "Booking History" if action_name == "booking_history"
      else
        append_breadcrumb "New"
      end
    end

    def guest_params
      params.require(:guest).permit(
        :name, :email, :phone, :home_address, :city, :state_code, :postal_code,
        :address_country, :tin, :country, :gender, :document_type, :government_id, :date_of_birth
      )
    end



    def authorize_view_guest_records!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_guest_records", hotel: current_hotel)
    end

    def authorize_manage_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
    end

    def authorize_delete_guest_record!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("delete_guest_record", hotel: current_hotel)
    end
  end
end
