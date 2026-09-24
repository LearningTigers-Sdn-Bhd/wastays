# frozen_string_literal: true

module Public
  module Concierge
    class CheckInsController < BaseController
      before_action :load_booking_from_cookie, only: [ :check_in_now, :submit_check_in, :check_in_success ]

      def new; end

      def lookup
        booking = resolve_concierge_booking_from_params(
          not_found_message: "Booking not found. Please check your confirmation code.",
          fallback_message: "Something went wrong. Please try again."
        )
        return unless booking

        case booking.status
        when "checked_in"
          redirect_to concierge_check_in_success_path(@hotel.unique_id, @hotel.public_id)
        when "completed"
          @error = "This booking has already been checked out."
          render(:new, status: :unprocessable_content)
        when "cancelled"
          @error = "This booking has been cancelled."
          render(:new, status: :unprocessable_content)
        when "confirmed"
          booking.create_pre_checkin!(
            status: "pending", document_status: "pending", signature_status: "pending"
          ) unless booking.pre_checkin.present?
          set_concierge_booking_cookie(booking)
          redirect_to concierge_check_in_now_path(@hotel.unique_id, @hotel.public_id)
        else
          @error = "This booking is not ready for check-in. Please see the front desk."
          render(:new, status: :unprocessable_content)
        end
      end

      def check_in_now
        return redirect_to concierge_check_in_path(@hotel.unique_id, @hotel.public_id) unless @booking
        @form = ::Concierge::CheckInForm.new(booking: @booking)
        @presenter = ::Public::Concierge::CheckInPresenter.new(booking: @booking, hotel: @hotel)
      end

      def submit_check_in
        return redirect_to concierge_check_in_path(@hotel.unique_id, @hotel.public_id) unless @booking

        @form = ::Concierge::CheckInForm.new(booking: @booking, params: check_in_form_params)
        @presenter = ::Public::Concierge::CheckInPresenter.new(booking: @booking, hotel: @hotel)

        if @form.needs_registration?
          if @form.save
            redirect_to concierge_check_in_now_path(@hotel.unique_id, @hotel.public_id), notice: "Registration completed successfully. Please confirm your check-in."
            return
          else
            @error_code = :registration_error
            @error = @form.errors.full_messages.to_sentence.presence || @presenter.error_message_for(:registration_error)
            render(:check_in_now, status: :unprocessable_content)
            return
          end
        end

        result = ::Concierge::SelfCheckIn.new(
          booking: @booking,
          latitude: params[:latitude],
          longitude: params[:longitude]
        ).call

        if result.success?
          session[:concierge_check_in_room] = result.room_number
          redirect_to concierge_check_in_success_path(@hotel.unique_id, @hotel.public_id)
        else
          @error_code = result.error_code
          @error = @presenter.error_message_for(@error_code) ||
                   result.message.presence ||
                   "Something went wrong. Please try again or see the front desk."
          render(:check_in_now, status: :unprocessable_content)
        end
      end

      def check_in_success
        @room_number = session.delete(:concierge_check_in_room) ||
                       @booking&.booking_rooms&.first&.room_number
        redirect_to concierge_home_path(@hotel.unique_id, @hotel.public_id) unless @booking
      end

      private

      def load_booking_from_cookie
        @booking = current_concierge_booking
      end

      def check_in_form_params
        params.require(:booking).permit(
          :guest_name,
          :guest_email,
          :guest_phone,
          :guest_city,
          :guest_state_code,
          :guest_postal_code,
          :guest_address_country,
          :guest_tin,
          :guest_country,
          :guest_document_type,
          :guest_government_id,
          :guest_passport_number,
          :guest_date_of_birth,
          :guest_home_address,
          :id_front,
          :id_back,
          :signature
        )
      rescue ActionController::ParameterMissing
        {}
      end
    end
  end
end
