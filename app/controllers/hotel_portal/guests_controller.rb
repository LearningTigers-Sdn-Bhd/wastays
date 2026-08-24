# frozen_string_literal: true

module HotelPortal
  class GuestsController < HotelPortal::BaseController
    helper_method :guest_stays_count, :guest_currency_totals

    before_action -> { require_feature!("unified_guest_profile") }
    before_action :authorize_view_guest_records!, only: %i[index show]
    before_action :authorize_manage_bookings!, only: %i[search check_banned new create edit update toggle_vip toggle_blacklist]
    before_action :authorize_delete_guest_record!, only: %i[destroy bulk_destroy]
    before_action :set_guest, only: [ :show, :edit, :update, :destroy, :toggle_vip, :toggle_blacklist ]
    before_action :set_breadcrumbs, only: [ :show, :new, :create, :edit, :update ]

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
            country: guest.country,
            gender: guest.gender,
            date_of_birth: guest.date_of_birth&.iso8601,
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

    def show
      @presenter = Guests::GuestPresenter.new(@guest)
      query = Guests::GuestBookingsQuery.new(hotel: current_hotel, guest: @guest)
      @all_bookings = query.all_bookings
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

    def toggle_vip
      @guest.update!(vip: !@guest.vip)
      redirect_to hotel_guest_path(current_hotel, @guest), notice: "Guest VIP status updated."
    end

    def toggle_blacklist
      is_blacklisted_here = @guest.blacklisted_at?(current_hotel)
      hotel_id = current_hotel.id
      @guest.metadata ||= {}

      if is_blacklisted_here
        if @guest.metadata["blacklisted_hotel_ids"].is_a?(Array)
          @guest.metadata["blacklisted_hotel_ids"].delete(hotel_id)
        end
        @guest.metadata["blacklist_details"]&.delete(hotel_id.to_s)
        if @guest.metadata["blacklisted_hotel_ids"].blank?
          @guest.blacklisted = false
        else
          @guest.blacklisted = @guest.metadata["blacklisted_hotel_ids"].any?
        end
      else
        reason = params[:blacklist_reason].to_s.strip
        if reason.blank?
          return redirect_to hotel_guest_path(current_hotel, @guest), alert: "Please provide a reason to blacklist this guest."
        end

        @guest.metadata["blacklisted_hotel_ids"] ||= []
        @guest.metadata["blacklisted_hotel_ids"] << hotel_id
        @guest.metadata["blacklisted_hotel_ids"].uniq!
        @guest.metadata["blacklist_details"] ||= {}
        @guest.metadata["blacklist_details"][hotel_id.to_s] = {
          "reason" => reason,
          "blacklisted_by_id" => current_user.id,
          "blacklisted_by_name" => current_user.name,
          "blacklisted_at" => Time.current.iso8601
        }
        @guest.blacklisted = true
      end
      @guest.save!

      redirect_to hotel_guest_path(current_hotel, @guest), notice: "Guest blacklist status updated."
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
        append_breadcrumb presenter.name, hotel_guest_path(current_hotel, @guest)
        append_breadcrumb "Edit" if action_name.in?([ "edit", "update" ])
      else
        append_breadcrumb "New"
      end
    end

    def guest_params
      params.require(:guest).permit(:name, :email, :phone, :city, :state_code, :postal_code, :tin, :country, :gender, :document_type, :government_id, :date_of_birth)
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
