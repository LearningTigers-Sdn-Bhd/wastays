# frozen_string_literal: true

module HotelPortal
  # Slot rows on the Boat Settings page. Slots are archived rather than
  # destroyed: a guest already booked on one still resolves their meals through
  # it, so removing the row outright would rewrite history.
  class BoatSchedulesController < HotelPortal::BaseController
    before_action :authorize_manage_profile!
    before_action :set_slot, only: %i[update destroy restore]

    def create
      slot = current_hotel.hotel_boat_schedules.new(slot_params)
      apply_meal_defaults(slot)

      if slot.save
        redirect_to hotel_boat_settings_path(current_hotel), notice: "Boat slot added."
      else
        redirect_to hotel_boat_settings_path(current_hotel), alert: slot.errors.full_messages.to_sentence
      end
    end

    def update
      if @slot.update(slot_params)
        redirect_to hotel_boat_settings_path(current_hotel), notice: "Boat slot updated."
      else
        redirect_to hotel_boat_settings_path(current_hotel), alert: @slot.errors.full_messages.to_sentence
      end
    end

    def destroy
      @slot.archive!
      redirect_to hotel_boat_settings_path(current_hotel), notice: "Boat slot retired. Existing bookings keep it."
    end

    def restore
      @slot.restore!
      redirect_to hotel_boat_settings_path(current_hotel), notice: "Boat slot restored."
    end

    private

    def set_slot
      @slot = current_hotel.hotel_boat_schedules.find(params[:id])
    end

    def slot_params
      params.require(:hotel_boat_schedule).permit(:time, :kind, :has_breakfast, :has_lunch, :has_dinner)
    end

    # A new slot starts from the property's meal times, so staff are correcting
    # a sensible default rather than ticking three boxes from scratch. What is
    # saved on the row is what the report reads -- the meal times never are.
    def apply_meal_defaults(slot)
      return if slot_params.keys.any? { |key| key.start_with?("has_") }

      setting = current_hotel.hotel_boat_setting
      return if setting.blank?

      setting.meals_for(slot.time, slot.kind).each { |meal, served| slot.public_send(:"has_#{meal}=", served) }
    end

    def authorize_manage_profile!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end
  end
end
