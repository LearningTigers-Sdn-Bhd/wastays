# frozen_string_literal: true

module HotelPortal
  module Bookings
    class GuestRegistrationNoteTemplatesController < HotelPortal::BaseController
      before_action :authorize_manage_bookings!
      before_action :set_booking
      before_action :set_template, only: %i[edit update destroy]

      def index
        @templates = current_hotel.guest_registration_note_templates.order(created_at: :desc)
        @template = current_hotel.guest_registration_note_templates.build
      end

      def new
        @template = current_hotel.guest_registration_note_templates.build
      end

      def create
        @template = current_hotel.guest_registration_note_templates.build(template_params)

        if @template.save
          redirect_to hotel_booking_guest_registration_note_templates_path(current_hotel, @booking)
        else
          @templates = current_hotel.guest_registration_note_templates.order(created_at: :desc)
          render :index, status: :unprocessable_content
        end
      end

      def edit
      end

      def update
        if @template.update(template_params)
          redirect_to hotel_booking_guest_registration_note_templates_path(current_hotel, @booking)
        else
          render :edit, status: :unprocessable_content
        end
      end

      def destroy
        @template.destroy
        redirect_to hotel_booking_guest_registration_note_templates_path(current_hotel, @booking)
      end

      private

      def set_booking
        @booking = current_hotel.bookings.find(params[:booking_id])
      end

      def set_template
        @template = current_hotel.guest_registration_note_templates.find(params[:id])
      end

      def template_params
        params.require(:guest_registration_note_template).permit(:title, :content)
      end

      def authorize_manage_bookings!
        has_perm = current_user.has_permission?("manage_bookings", hotel: current_hotel) ||
                   current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
        raise Pundit::NotAuthorizedError unless has_perm
      end
    end
  end
end
