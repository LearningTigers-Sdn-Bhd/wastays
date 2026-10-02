# frozen_string_literal: true

module CorporatePortal
  # An agent booking a stay for a guest.
  #
  # Scoped to the hotels this account actually has an active relationship with:
  # the portal is the agent's own, so the hotel list is theirs, and a hotel they
  # are not linked to is not found rather than forbidden.
  class BookingsController < CorporatePortal::BaseController
    # `index` and `show` list stays the account already has, so they survive a
    # hotel revoking the permission. Only taking a new room is refused.
    before_action :require_booking_permission!, only: %i[new create]
    before_action :load_relationships, only: %i[index]
    before_action :load_bookable_relationships, only: %i[new create]
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

      # Submissions and payment stages are preloaded: the payment chip asks about
      # both for every row on the page.
      @pagy, @bookings = pagy(:offset,
        scope.includes(:hotel, :ar_payment_submissions, :payment_instalments, :hotel_corporate_account)
             .order(created_at: :desc, id: :desc),
        limit: page_size)
      @payment_presenters = payment_presenters_for(@bookings)
      @stay_sizes = stay_sizes_for(@bookings)
    end

    # The booking wizard: the stay (hotel and dates), the rooms (a cart of lines,
    # each a category, a party and a rate), then the guests. Where the agent has got
    # to, including the whole cart, is carried in the URL, so Back and reload behave
    # and any step can be returned to.
    WIZARD_STEPS = %i[stay rooms guests].freeze
    # Within the rooms step: the cart itself, then adding a line -- choose a
    # category, say who is in the room, choose a rate for that party.
    ROOM_STAGES = %i[cart category occupancy rate].freeze

    def new
      @relationship = relationship_for_request
      @check_in = parse_date(params[:check_in])
      @check_out = parse_date(params[:check_out])
      @lines = StayLine.parse(params[:lines])

      @step = :stay
      return if @relationship.blank? || @check_in.blank? || @check_out.blank?

      # One search validates the dates and says which categories have rooms free,
      # whoever is going to sleep in them. A category is priced for a party, and one
      # may sell only from two adults up, so it is asked for one and for two; a
      # category either answers is listed.
      @base = search_for(adults: 1, children: 0, rooms: 1)
      return if @base.error.present?

      @base_options = @base.options + search_for(adults: 2, children: 0, rooms: 1).options

      @cart = AgentStayCart.call(
        hotel: @relationship.hotel, relationship: @relationship, check_in: @check_in, check_out: @check_out, lines: @lines
      )
      @free_rooms = free_rooms_by_category
      @step = wizard_step
      load_rooms_stage if @step == :rooms
      @room_slots = @cart.quotes.flat_map { |quote| Array.new(quote.rooms, quote) } if @step == :guests
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

    # What each room card reads (CorporatePortal::BookingDetailPresenter).
    ROOM_DETAIL_INCLUDES = [ { booking_rooms: %i[room_type rate_plan] }, { booking_guests: :guest } ].freeze

    def show
      @booking = corporate_bookings.includes(:hotel, :ar_payment_submissions, :hotel_corporate_account, :corporate_booked_by, *ROOM_DETAIL_INCLUDES).find(params[:id])
      @payment = payment_presenters_for([ @booking ]).fetch(@booking.id)
      # A multi-room stay is several bookings under one group; the confirmation
      # should show the stay, not one room of it.
      @bookings = if @booking.group_booking_id.present?
        corporate_bookings.where(group_booking_id: @booking.group_booking_id).includes(:hotel, *ROOM_DETAIL_INCLUDES).order(:group_position, :id)
      else
        [ @booking ]
      end
      # The same object the controller would act through, so the button is shown
      # only when cancelling would actually be allowed.
      @stay_cancellation = CancelAgentBooking.new(booking: @booking, user: current_user)
      @room_cancellation = CancelAgentBooking.new(booking: @booking, user: current_user, whole_stay: false)
    end

    private

    # The furthest step the choices so far allow, or an earlier one the agent asked
    # to go back to. A step is never shown ahead of what it needs.
    def wizard_step
      furthest = @lines.any? && @cart.success? ? :guests : :rooms
      requested = params[:step].to_s.to_sym
      return furthest unless WIZARD_STEPS.include?(requested)

      WIZARD_STEPS.index(requested) <= WIZARD_STEPS.index(furthest) ? requested : furthest
    end

    def search_for(adults:, children:, rooms:, child_ages: [])
      AgentStaySearch.call(
        hotel: @relationship.hotel, check_in: @check_in, check_out: @check_out,
        adults: adults, children: children, child_ages: child_ages, rooms: rooms, relationship: @relationship
      )
    end

    # What each category has left for another line: its free rooms, less what the
    # stay already holds. Only categories the agency is offered a rate on appear.
    def free_rooms_by_category
      held = @lines.group_by(&:room_type_id).transform_values { |lines| lines.sum(&:quantity) }
      @base_options.group_by(&:room_type).to_h do |room_type, options|
        [ room_type, [ options.first.available_count - held.fetch(room_type.id, 0), 0 ].max ]
      end
    end

    # The stage of the rooms step, and what it needs loaded. A stage is only shown
    # when what it needs is there: asking for a rate without a party falls back to
    # asking who the party is.
    def load_rooms_stage
      @add_room_type = @free_rooms.keys.find { |room_type| room_type.id.to_s == params[:add_room_type_id].to_s }
      @add_adults = [ params[:add_adults].presence&.to_i || 2, 1 ].max
      @add_children = [ params[:add_children].to_i, 0 ].max
      @add_child_ages = Bookings::ChildAges.normalize(params[:add_child_ages], @add_children)
      @add_quantity = [ params[:add_quantity].presence&.to_i || 1, 1 ].max

      requested = params[:stage].to_s.to_sym
      @stage = if requested == :rate && @add_room_type && add_party_ok? then :rate
      elsif requested.in?(%i[occupancy rate]) && @add_room_type then :occupancy
      elsif requested == :category || @lines.empty? then :category
      else :cart
      end

      return unless @stage == :rate

      result = search_for(adults: @add_adults, children: @add_children, child_ages: @add_child_ages, rooms: @add_quantity)
      @rate_options = result.options.select { |option| option.room_type.id == @add_room_type.id }
    end

    # The party fits the category, and the category has that many rooms left.
    def add_party_ok?
      if !@add_room_type.fits?(adults: @add_adults, children: @add_children)
        @add_error = @add_room_type.occupancy_limit_message
      elsif @add_quantity > @free_rooms.fetch(@add_room_type, 0)
        @add_error = "#{@add_room_type.name} has #{ActionController::Base.helpers.pluralize(@free_rooms.fetch(@add_room_type, 0), 'room')} left for these dates."
      end
      @add_error.blank?
    end

    # How many rooms each multi-room stay on this page has, so a row can say it is
    # one of several. Counted across the whole account, not just the page.
    def stay_sizes_for(bookings)
      group_ids = bookings.filter_map(&:group_booking_id).uniq
      return {} if group_ids.empty?

      corporate_bookings.where(group_booking_id: group_ids).group(:group_booking_id).count
    end

    # Keyed by booking id, so a view can ask for one row's payment state without
    # reaching back into the database.
    def payment_presenters_for(bookings)
      bookings.to_a.index_by(&:id).transform_values do |booking|
        CorporatePortal::BookingPaymentPresenter.new(booking)
      end
    end

    def require_booking_permission!
      return if may_book_anywhere?

      redirect_to corporate_bookings_path,
                  alert: "None of your linked hotels have enabled bookings for this account yet."
    end

    # Every linked hotel, so the list can still be filtered by a hotel that has
    # since stopped letting this account book.
    def load_relationships
      @relationships = corporate_relationships.active.includes(:hotel).order("hotels.name")
    end

    # Only the hotels that granted the permission: one the account is merely
    # billed by is not a hotel it can reserve at, and must not appear in the
    # picker or resolve from a hand-built URL.
    def load_bookable_relationships
      @relationships = bookable_relationships.includes(:hotel).order("hotels.name")
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
        :room_type_id, :rate_plan_id, :check_in, :check_out, :adults, :children, :rooms,
        :special_requests, :agent_reference, :boat_in_time, :boat_out_time, :boat_in_custom_time, :boat_out_custom_time,
        child_ages: [], rooms_detail: {},
        lines: [ :room_type_id, :rate_plan_id, :adults, :children, :quantity, :child_ages ]
      )
    end

    def redirect_back_to_search
      # The older single-category post is read as one line.
      lines = StayLine.parse(booking_params[:lines]).presence ||
              StayLine.parse([ booking_params.to_h.slice("room_type_id", "rate_plan_id", "adults", "children", "child_ages")
                                             .merge("quantity" => booking_params[:rooms]) ])
      redirect_to new_corporate_booking_path(
        hotel_relationship_id: @relationship.id,
        check_in: booking_params[:check_in], check_out: booking_params[:check_out],
        lines: StayLine.to_params(lines), step: "guests"
      ), alert: flash.now[:alert]
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
