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
      @bookings = corporate_bookings.includes(:hotel).order(check_in: :asc).limit(50)
    end

    # The search form, and its results once dates are given.
    def new
      @relationship = find_relationship(params[:hotel_relationship_id])
      @check_in = parse_date(params[:check_in])
      @check_out = parse_date(params[:check_out])
      @adults = (params[:adults].presence || 2).to_i
      @children = params[:children].to_i
      @room_type_id = params[:room_type_id]

      return if @relationship.blank? || @check_in.blank? || @check_out.blank?

      @search = AgentStaySearch.call(
        hotel: @relationship.hotel, check_in: @check_in, check_out: @check_out,
        adults: @adults, children: @children
      )
      @selected = @search.options.find { |option| option.room_type.id.to_s == @room_type_id.to_s }
    end

    def create
      result = CreateAgentBooking.call(
        relationship: @relationship, params: booking_params, user: current_user
      )

      if result.success?
        redirect_to corporate_booking_path(result.booking), notice: "Booking confirmed."
      else
        flash.now[:alert] = result.errors.to_sentence
        redirect_back_to_search
      end
    end

    def show
      @booking = corporate_bookings.find(params[:id])
    end

    private

    def load_relationships
      @relationships = corporate_relationships.active.includes(:hotel).order("hotels.name")
    end

    def load_relationship
      @relationship = find_relationship(params[:hotel_relationship_id])
      redirect_to new_corporate_booking_path, alert: "Choose a hotel to book." if @relationship.blank?
    end

    def find_relationship(id)
      return nil if id.blank?

      @relationships.find { |relationship| relationship.id.to_s == id.to_s }
    end

    # Only bookings this account is the billed party on.
    def corporate_bookings
      Booking.where(hotel_corporate_account_id: corporate_relationships.select(:id))
    end

    # Guest blocks arrive keyed by position, so they are permitted as a hash and
    # read back in order by the service.
    def booking_params
      params.require(:booking).permit(
        :room_type_id, :check_in, :check_out, :adults, :children,
        :guest_name, :guest_email, :guest_phone, :special_requests,
        guests: {}
      )
    end

    def redirect_back_to_search
      redirect_to new_corporate_booking_path(
        hotel_relationship_id: @relationship.id,
        check_in: booking_params[:check_in], check_out: booking_params[:check_out],
        adults: booking_params[:adults], children: booking_params[:children],
        room_type_id: booking_params[:room_type_id]
      ), alert: flash.now[:alert]
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
