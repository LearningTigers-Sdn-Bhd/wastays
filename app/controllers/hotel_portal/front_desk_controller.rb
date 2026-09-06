# frozen_string_literal: true

module HotelPortal
  class FrontDeskController < HotelPortal::BaseController
    TABS = %w[bookings arrivals in_house departures checkout].freeze
    VIEWS = %w[list rooms].freeze

    before_action :set_allowed_tabs
    before_action :set_tab

    def index
      @view = VIEWS.include?(params[:view]) ? params[:view] : "rooms"
      @state = front_desk_state
      load_metrics

      case @tab
      when "bookings" then load_bookings
      when "arrivals" then load_arrivals
      when "in_house" then load_in_house
      when "departures" then load_departures
      when "checkout" then load_checkout
      end
    end

    private

    # Every tab exposes guest and stay records, so every tab needs a permission.
    # A user who qualifies for none has no business on this page at all.
    def set_allowed_tabs
      view_bookings = current_user.has_permission?("view_bookings", hotel: current_hotel)

      @allowed_tabs = TABS.select do |tab|
        tab == "arrivals" ? current_user.has_permission?("manage_guest_arrival", hotel: current_hotel) : view_bookings
      end

      raise Pundit::NotAuthorizedError if @allowed_tabs.empty?
    end

    def set_tab
      @tab = @allowed_tabs.include?(params[:tab]) ? params[:tab] : @allowed_tabs.first
    end

    def load_metrics
      @metrics = {}
      @metrics["bookings"] = current_hotel.bookings.count if @allowed_tabs.include?("bookings")
      @metrics["arrivals"] = HotelPortal::FrontDesk::ArrivalsQuery.new(hotel: current_hotel, params: query_params).total_count if @allowed_tabs.include?("arrivals")
      @metrics["in_house"] = HotelPortal::InHouseGuestsQuery.new(hotel: current_hotel, params: in_house_params).in_house_count if @allowed_tabs.include?("in_house")
      @metrics["departures"] = HotelPortal::FrontDesk::DeparturesQuery.new(hotel: current_hotel, params: query_params).total_count if @allowed_tabs.include?("departures")
      @metrics["checkout"] = HotelPortal::FrontDesk::CheckoutQuery.new(hotel: current_hotel, params: query_params).total_count if @allowed_tabs.include?("checkout")
    end

    def load_bookings
      query = HotelPortal::FrontDesk::BookingsQuery.new(hotel: current_hotel, params: booking_params)
      @query = query.query
      @booking_status = query.status
      @start_date = query.start_date
      @end_date = query.end_date
      paginate_bookings(query.call, :booking_page)
    end

    def load_arrivals
      query = HotelPortal::FrontDesk::ArrivalsQuery.new(hotel: current_hotel, params: query_params)
      @start_date = query.start_date
      @end_date = query.end_date
      @query = query.query
      paginate_bookings(query.call, :arrival_page)
    end

    def load_in_house
      query = HotelPortal::InHouseGuestsQuery.new(hotel: current_hotel, params: in_house_params)
      @query = in_house_params[:query].to_s.strip
      @room_assignment = in_house_params[:room_assignment]
      paginate_bookings(query.call, :in_house_page)
    end

    def load_departures
      query = HotelPortal::FrontDesk::DeparturesQuery.new(hotel: current_hotel, params: query_params)
      @start_date = query.start_date
      @end_date = query.end_date
      @query = query.query
      paginate_bookings(query.call, :departure_page)
    end

    def load_checkout
      query = HotelPortal::FrontDesk::CheckoutQuery.new(hotel: current_hotel, params: query_params)
      @start_date = query.start_date
      @end_date = query.end_date
      @query = query.query
      paginate_bookings(query.call, :checkout_page)
    end

    def in_house_params
      room_assignment = params[:room_assignment].to_s
      { query: scalar_param(:in_house_query), room_assignment: %w[assigned unassigned].include?(room_assignment) ? room_assignment : nil }
    end

    def booking_params
      %i[booking_query booking_status booking_check_in_date booking_start_date booking_end_date start_date end_date].index_with { |key| scalar_param(key) }
    end

    def query_params
      %i[arrival_date arrival_start_date arrival_end_date arrival_q departure_start_date departure_end_date departure_query checkout_start_date checkout_end_date checkout_query start_date end_date].index_with { |key| scalar_param(key) }
    end

    def scalar_param(key)
      value = params[key]
      value if value.is_a?(String)
    end

    def paginate_bookings(scope, page_key)
      @page_param = page_key
      @pagy, @bookings = pagy(:offset, scope, limit: 25, page_key: page_key.to_s)
    end

    def front_desk_state
      %i[
        booking_query booking_status booking_check_in_date booking_start_date booking_end_date booking_page
        arrival_start_date arrival_end_date arrival_q arrival_page
        in_house_query room_assignment in_house_page
        departure_start_date departure_end_date departure_query departure_page
        checkout_start_date checkout_end_date checkout_query checkout_page
      ].index_with { |key| scalar_param(key) }.compact
    end
  end
end
