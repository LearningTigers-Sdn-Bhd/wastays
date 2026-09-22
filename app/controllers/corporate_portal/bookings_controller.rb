# frozen_string_literal: true

module CorporatePortal
  # An agent booking a stay for a guest.
  #
  # Scoped to the hotels this account actually has an active relationship with:
  # the portal is the agent's own, so the hotel list is theirs, and a hotel they
  # are not linked to is not found rather than forbidden.
  class BookingsController < CorporatePortal::BaseController
    before_action :load_relationships
    before_action :load_relationship, only: %i[create]

    def index
      page_size = CorporatePortal::BookingsIndexPresenter.normalize_page_size(params[:per_page])
      @index = CorporatePortal::BookingsIndexPresenter.new(
        relationships: @relationships,
        hotel_relationship_id: params[:hotel_relationship_id],
        status: params[:status],
        statuses_present: corporate_bookings.distinct.order(:status).pluck(:status),
        page_size: page_size
      )

      scope = corporate_bookings
      scope = scope.where(hotel_corporate_account_id: @index.selected_relationship.id) if @index.selected_relationship
      scope = scope.where(status: @index.selected_status) if @index.selected_status
      scope = scope.search(params[:q]) if params[:q].present?

      # Submissions are preloaded: the payment chip asks about them for every
      # row on the page.
      @pagy, @bookings = pagy(:offset,
        scope.includes(:hotel, :ar_payment_submissions, :hotel_corporate_account)
             .order(created_at: :desc, id: :desc),
        limit: page_size)
      @payment_presenters = payment_presenters_for(@bookings)
    end

    # The search form, and its results once dates are given.
    def new
      @relationship = relationship_for_request
      @check_in = parse_date(params[:check_in])
      @check_out = parse_date(params[:check_out])
      @adults = (params[:adults].presence || 2).to_i
      @children = params[:children].to_i
      @rooms = [ (params[:rooms].presence || 1).to_i, 1 ].max
      @room_type_id = params[:room_type_id]

      return if @relationship.blank? || @check_in.blank? || @check_out.blank?

      @search = AgentStaySearch.call(
        hotel: @relationship.hotel, check_in: @check_in, check_out: @check_out,
        adults: @adults, children: @children, rooms: @rooms
      )
      @selected = @search.options.find { |option| option.room_type.id.to_s == @room_type_id.to_s }
    end

    def create
      result = CreateAgentBooking.call(
        relationship: @relationship, params: booking_params, user: current_user
      )

      if result.success?
        redirect_to corporate_booking_path(result.booking),
                    notice: "#{ActionController::Base.helpers.pluralize(result.bookings.size, 'booking')} confirmed."
      else
        flash.now[:alert] = result.errors.to_sentence
        redirect_back_to_search
      end
    end

    def show
      @booking = corporate_bookings.includes(:hotel, :ar_payment_submissions, :hotel_corporate_account).find(params[:id])
      @payment = payment_presenters_for([ @booking ]).fetch(@booking.id)
      # A multi-room stay is several bookings under one group; the confirmation
      # should show the stay, not one room of it.
      @bookings = if @booking.group_booking_id.present?
        corporate_bookings.where(group_booking_id: @booking.group_booking_id).order(:group_position, :id)
      else
        [ @booking ]
      end
      # The same object the controller would act through, so the button is shown
      # only when cancelling would actually be allowed.
      @cancellation = CancelAgentBooking.new(booking: @booking, user: current_user)
    end

    private

    # Keyed by booking id, so a view can ask for one row's payment state without
    # reaching back into the database.
    def payment_presenters_for(bookings)
      bookings.to_a.index_by(&:id).transform_values do |booking|
        CorporatePortal::BookingPaymentPresenter.new(booking)
      end
    end

    def load_relationships
      @relationships = corporate_relationships.active.includes(:hotel).order("hotels.name")
    end

    def load_relationship
      @relationship = relationship_for_request
      redirect_to new_corporate_booking_path, alert: "Choose a hotel to book." if @relationship.blank?
    end

    # A single linked hotel is not a choice, so a request that names none
    # still resolves to it -- the form's own hidden field sends it on every
    # real submission, but a bookmarked or hand-built URL works the same way.
    # An id that was given and simply does not match, though, must still
    # refuse outright: silently substituting this account's own hotel for one
    # it is not linked to would hide exactly the request this guards against.
    def relationship_for_request
      return find_relationship(params[:hotel_relationship_id]) if params[:hotel_relationship_id].present?

      @relationships.first if @relationships.one?
    end

    def find_relationship(id)
      return nil if id.blank?

      @relationships.find { |relationship| relationship.id.to_s == id.to_s }
    end

    # Rooms, and the guest blocks inside them, arrive keyed by position. They
    # are permitted as a nested hash and read back in order by the service,
    # which takes only the guest keys it knows.
    def booking_params
      params.require(:booking).permit(
        :room_type_id, :check_in, :check_out, :adults, :children, :rooms,
        :special_requests, rooms_detail: {}
      )
    end

    def redirect_back_to_search
      redirect_to new_corporate_booking_path(
        hotel_relationship_id: @relationship.id,
        check_in: booking_params[:check_in], check_out: booking_params[:check_out],
        adults: booking_params[:adults], children: booking_params[:children],
        rooms: booking_params[:rooms], room_type_id: booking_params[:room_type_id]
      ), alert: flash.now[:alert]
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
