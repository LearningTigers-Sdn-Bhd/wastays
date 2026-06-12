# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Show
      module Actions
        class ManageGuestsController < BaseController
          MODES = %w[add edit_primary edit_additional].freeze

          before_action :set_mode
          before_action :set_additional_booking_guest, if: -> { @mode == "edit_additional" }

          def show
            return create_additional if request.post? && @mode == "add"
            return update_guest if request.patch? && @mode != "add"
            raise ActiveRecord::RecordNotFound unless request.get?

            prepare_guest
            render_sheet
          end

          private

          def set_mode
            @mode = params[:mode].presence_in(MODES) || "add"
          end

          def set_additional_booking_guest
            @booking_guest = @booking.booking_guests.find_by!(id: params[:booking_guest_id], is_primary: false)
          end

          def prepare_guest
            @guest = if @mode == "edit_additional"
              @booking_guest.guest
            elsif @mode == "edit_primary"
              Guest.new(primary_guest_attributes)
            else
              Guest.new(country: current_hotel.country.presence || "Malaysia", document_type: "ic")
            end
          end

          def create_additional
            @guest = Guest.new(guest_params)
            @guest.created_by_hotel = current_hotel
            if @guest.valid?
              ActiveRecord::Base.transaction do
                @guest.save!
                @booking.booking_guests.create!(guest: @guest, is_primary: false)
              end
              return complete_action(notice: "Guest added.")
            end

            render_sheet(status: :unprocessable_content)
          end

          def update_guest
            return update_primary if @mode == "edit_primary"

            @guest = @booking_guest.guest
            return complete_action(notice: "Guest updated.") if @guest.update(guest_params)

            render_sheet(status: :unprocessable_content)
          end

          def update_primary
            @guest = Guest.new(guest_params)
            return render_sheet(status: :unprocessable_content) unless @guest.valid?

            result = ::Bookings::UpdateStayService.new(
              booking: @booking,
              params: primary_booking_params,
              user: current_user
            ).call
            if result.success?
              @booking.reload.primary_guest&.update!(guest_params)
              return complete_action(notice: "Primary guest updated.")
            end

            result.errors.each { |error| @guest.errors.add(:base, error) }
            render_sheet(status: :unprocessable_content)
          end

          def primary_guest_attributes
            {
              name: @presenter.primary_guest_name,
              email: @presenter.primary_guest_email,
              phone: @presenter.primary_guest_phone,
              country: @presenter.primary_guest_country == "—" ? nil : @presenter.primary_guest_country,
              gender: @booking.guest_gender,
              document_type: @presenter.primary_guest_document_type.to_s.downcase,
              government_id: @presenter.primary_guest_government_id == "—" ? nil : @presenter.primary_guest_government_id
            }
          end

          def primary_booking_params
            {
              guest_name: guest_params[:name],
              guest_email: guest_params[:email],
              guest_phone: guest_params[:phone],
              guest_country: guest_params[:country],
              guest_gender: guest_params[:gender],
              guest_document_type: guest_params[:document_type],
              guest_government_id: guest_params[:government_id]
            }
          end

          def guest_params
            params.require(:guest).permit(:name, :email, :phone, :country, :gender, :document_type, :government_id)
          end

          def render_sheet(status: :ok)
            render "hotel_portal/bookings/show/actions/manage_guest/offcanvas", status: status
          end
        end
      end
    end
  end
end
