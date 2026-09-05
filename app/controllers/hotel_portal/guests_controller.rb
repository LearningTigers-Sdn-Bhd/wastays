# frozen_string_literal: true

module HotelPortal
  class GuestsController < HotelPortal::BaseController
    include SheetActionCompletion

    helper_method :guest_stays_count, :guest_currency_totals

    TAB_ACTIONS = %i[details booking_history].freeze
    STATUS_ACTIONS = %i[vip unvip blacklist unblacklist].freeze
    BULK_STATUS_ACTIONS = %i[bulk_vip bulk_unvip bulk_blacklist bulk_unblacklist].freeze

    before_action -> { require_feature!("unified_guest_profile") }
    before_action :authorize_view_guest_records!, only: [ :index, :show, *TAB_ACTIONS ]
    before_action :authorize_manage_bookings!, only: [ :search, :check_banned, :new, :create, :edit, :update, *STATUS_ACTIONS, *BULK_STATUS_ACTIONS ]
    before_action :authorize_delete_guest_record!, only: %i[destroy bulk_destroy]
    before_action :set_guest, only: [ :show, :edit, :update, :destroy, *TAB_ACTIONS, *STATUS_ACTIONS ]
    before_action :set_breadcrumbs, only: [ :new, :create, :edit, :update, *TAB_ACTIONS ]

    def index
      unless current_hotel
        @guests = Guest.none.page(params[:page]).per(25)
        @country_options = []
        @tag_counts = Hash.new(0)
        @repeat_ids = Set.new
        @guest_stays_count = {}
        @guest_currency_totals = {}
        return
      end

      query = Guests::GuestQuery.new(hotel: current_hotel, params: params)

      @guests = query.call.page(params[:page]).per(25)
      @country_options = query.country_options
      @tag_counts = query.tag_counts

      guest_ids = @guests.map(&:id)
      @repeat_ids = Guests::GuestQuery.repeat_ids(guest_ids)

      stats = Guests::StatsService.new(hotel: current_hotel, guest_ids: guest_ids).call
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
            document_type: guest.document_type,
            government_id: guest.safely_read_encrypted(:government_id),
            passport_number: guest.safely_read_encrypted(:passport_number),
            tin: guest.tin,
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

    # New and edit are the same sheet, served into the shell's action-sheet
    # frame. `return_to` carries the caller, so New lands back on the directory
    # and Edit lands back on the record it was opened from.
    def new
      # The country is prefilled because the state field reads it. The city is
      # not: the property's city is a likely answer, not a known one, so it is
      # offered as a placeholder and the desk types what the guest says.
      @guest = Guest.new(
        country: current_hotel.country,
        address_country: current_hotel.country
      )
      render layout: false
    end

    def create
      @guest = Guest.new(guest_params)
      @guest.created_by_hotel = current_hotel

      if @guest.save
        finish_sheet("Guest record created successfully.", fallback: details_hotel_guest_path(current_hotel, @guest))
      else
        render :new, layout: false, status: :unprocessable_content
      end
    end

    def edit
      render layout: false
    end

    def update
      return update_section if params[:section].present?

      if @guest.update(guest_params)
        finish_sheet("Guest record updated successfully.", fallback: details_hotel_guest_path(current_hotel, @guest))
      else
        render :edit, layout: false, status: :unprocessable_content
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
      result = Guests::BulkDestroyService.new(guest_ids: selected_guest_ids, hotel: current_hotel).call

      if result.success?
        redirect_to hotel_guests_path(current_hotel), notice: result.message, status: :see_other
      else
        redirect_to hotel_guests_path(current_hotel), alert: result.message, status: :see_other
      end
    end

    # The same services the row menu uses. They already take a collection, so a
    # selection of one and a selection of forty follow the same path.
    def bulk_vip
      apply_bulk(Guests::SetVip.new(guests: selected_guests, hotel: current_hotel, vip: true))
    end

    def bulk_unvip
      apply_bulk(Guests::SetVip.new(guests: selected_guests, hotel: current_hotel, vip: false))
    end

    def bulk_blacklist
      apply_bulk(Guests::SetBlacklist.new(
        guests: selected_guests, hotel: current_hotel, blacklisted: true,
        actor: current_user, reason: params[:blacklist_reason]
      ))
    end

    def bulk_unblacklist
      apply_bulk(Guests::SetBlacklist.new(
        guests: selected_guests, hotel: current_hotel, blacklisted: false, actor: current_user
      ))
    end



    def guest_stays_count(guest)
      @guest_stays_count.fetch(guest.id, 0)
    end

    def guest_currency_totals(guest)
      @guest_currency_totals.fetch(guest.id, {})
    end

    private

    # The details tab is four blocks, each with its own Save. A save writes the
    # fields of the block that sent it and nothing else: a tax form that carried
    # blank address keys would wipe the address on every submit.
    def update_section
      section = params[:section].to_s
      fields = Guests::GuestPresenter::SECTIONS.dig(section, :fields)
      raise ActiveRecord::RecordNotFound if fields.blank?

      saved = @guest.update(guest_params.slice(*fields))
      @presenter = Guests::GuestPresenter.new(@guest)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: section_streams(section, saved: saved),
                 status: saved ? :ok : :unprocessable_content
        end
        format.html do
          destination = details_hotel_guest_path(current_hotel, @guest)

          if saved
            redirect_to destination, notice: "Guest record updated successfully.", status: :see_other
          else
            redirect_to destination, alert: @guest.errors.full_messages.to_sentence, status: :see_other
          end
        end
      end
    end

    # Only the block that saved is replaced, so the other three keep whatever
    # the desk had typed into them. The header comes along when the identity
    # block saves, because it carries the name and the contact line.
    def section_streams(section, saved:)
      streams = [
        helpers.turbo_stream.replace(
          "guest_section_#{section}",
          partial: "hotel_portal/guests/details_section",
          locals: { guest: @guest, section: section }
        )
      ]

      return streams unless saved

      if section == "identity"
        streams << helpers.turbo_stream.replace(
          "guest-record-header",
          partial: "hotel_portal/guests/record_header",
          locals: { guest: @guest, presenter: @presenter }
        )
      end

      streams << toast_stream("#{Guests::GuestPresenter::SECTIONS.dig(section, :title)} saved.", type: :success)
      streams
    end

    def apply_bulk(service)
      result = service.call
      destination = hotel_guests_path(current_hotel, filter_params)

      if result.success?
        redirect_to destination, notice: result.message, status: :see_other
      else
        redirect_to destination, alert: result.message, status: :see_other
      end
    end

    # The selection travels as a JSON array in one hidden field, so the browser
    # never has to serialise forty separate inputs.
    def selected_guest_ids
      ids = JSON.parse(params[:guest_ids].presence || "[]")
      ids.is_a?(Array) ? ids : []
    rescue JSON::ParserError
      []
    end

    def selected_guests
      Guest.kept.where(id: selected_guest_ids).for_hotel(current_hotel).to_a
    end

    # Keep the tab and search the user was on when they acted.
    def filter_params
      params.permit(:tag, :query, :country).to_h.compact_blank
    end

    def finish_sheet(notice, fallback:)
      complete_sheet_action(
        destination: sheet_action_return_to(fallback: fallback),
        notice: notice,
        frame: turbo_frame_request_id.presence || "settings_action_sheet"
      )
    end

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

    # Edit is a sheet and renders no layout, so it gets no crumb of its own.
    def set_breadcrumbs
      if @guest&.persisted?
        presenter = Guests::GuestPresenter.new(@guest)
        append_breadcrumb presenter.name, details_hotel_guest_path(current_hotel, @guest)
        append_breadcrumb "Booking History" if action_name == "booking_history"
      else
        append_breadcrumb "New"
      end
    end

    def guest_params
      params.require(:guest).permit(
        :name, :email, :phone, :home_address, :city, :state_code, :postal_code,
        :address_country, :tin, :country, :gender, :document_type, :government_id,
        :passport_number, :date_of_birth
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
