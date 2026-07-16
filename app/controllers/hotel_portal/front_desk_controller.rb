# frozen_string_literal: true

module HotelPortal
  class FrontDeskController < HotelPortal::BaseController
    TABS = %w[bookings arrivals in_house departures].freeze
    VIEWS = %w[list rooms].freeze

    before_action :set_allowed_tabs
    before_action :set_tab

    def index
      @view = VIEWS.include?(params[:view]) ? params[:view] : "list"
      load_metrics

      case @tab
      when "bookings" then load_bookings
      when "arrivals" then load_arrivals
      when "in_house" then load_in_house
      when "departures" then load_departures
      end
    end

    private

    def set_allowed_tabs
      @allowed_tabs = %w[in_house departures]
      @allowed_tabs.unshift("arrivals") if current_user.has_permission?("manage_guest_arrival", hotel: current_hotel)
      @allowed_tabs.unshift("bookings") if current_user.has_permission?("view_bookings", hotel: current_hotel)
    end

    def set_tab
      @tab = @allowed_tabs.include?(params[:tab]) ? params[:tab] : @allowed_tabs.first
    end

    def load_metrics
      @metrics = {}
      @metrics["bookings"] = current_hotel.bookings.count if @allowed_tabs.include?("bookings")
      @metrics["arrivals"] = HotelPortal::FrontDesk::ArrivalsQuery.new(hotel: current_hotel, params: query_params).total_count if @allowed_tabs.include?("arrivals")
      in_house_query = HotelPortal::InHouseGuestsQuery.new(hotel: current_hotel, params: in_house_params)
      @metrics["in_house"] = in_house_query.in_house_count
      @metrics["departures"] = HotelPortal::FrontDesk::DeparturesQuery.new(hotel: current_hotel, params: query_params).total_count
    end

    def load_bookings
      query = HotelPortal::FrontDesk::BookingsQuery.new(hotel: current_hotel, params: booking_params)
      @query = query.query
      @booking_status = query.status
      @start_date = query.start_date
      @end_date = query.end_date
      @page_param = :booking_page
      @bookings = query.call.page(page_param(:booking_page)).per(25)
    end

    def load_arrivals
      query = HotelPortal::FrontDesk::ArrivalsQuery.new(hotel: current_hotel, params: query_params)
      @start_date = query.start_date
      @end_date = query.end_date
      @query = query.query
      @page_param = :arrival_page
      @bookings = query.call.page(page_param(:arrival_page)).per(25)
    end

    def load_in_house
      query = HotelPortal::InHouseGuestsQuery.new(hotel: current_hotel, params: in_house_params)
      @query = in_house_params[:query].to_s.strip
      @room_assignment = in_house_params[:room_assignment]
      @page_param = :in_house_page
      @bookings = query.call.page(page_param(:in_house_page)).per(25)
    end

    def load_departures
      query = HotelPortal::FrontDesk::DeparturesQuery.new(hotel: current_hotel, params: query_params)
      @start_date = query.start_date
      @end_date = query.end_date
      @query = query.query
      @page_param = :departure_page
      @bookings = query.call.page(page_param(:departure_page)).per(25)
    end

    def in_house_params
      room_assignment = params[:room_assignment].to_s
      { query: scalar_param(:in_house_query), room_assignment: %w[assigned unassigned].include?(room_assignment) ? room_assignment : nil }
    end

    def booking_params
      %i[booking_query booking_status booking_check_in_date start_date end_date].index_with { |key| scalar_param(key) }
    end

    def query_params
      %i[arrival_date start_date end_date arrival_q departure_query].index_with { |key| scalar_param(key) }
    end

    def scalar_param(key)
      value = params[key]
      value if value.is_a?(String)
    end

    def page_param(key)
      value = Integer(params[key], exception: false).to_i
      value.positive? ? value : 1
    end
  end
end
