# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class SourcesController < BaseController
        before_action :load_travel_agent_accounts
        helper_method :selected_source, :current_source_label, :apply_to_group?

        def show
          return update if request.patch?

          @locked_reason = ::Bookings::ChangeSource.locked_reason(@booking)
          render :show, layout: false
        end

        private

        def update
          result = ::Bookings::ChangeSource.call(booking: @booking, actor: current_user, **source_params)
          return complete_action(notice: "Booking source updated.") if result.success?

          @errors = result.errors
          @locked_reason = ::Bookings::ChangeSource.locked_reason(@booking)
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/sources/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end

        def source_params
          params.fetch(:booking, {}).permit(:source, :travel_agent_account_id, :apply_to_group).to_h.symbolize_keys
        end

        def selected_source
          source_params[:source] || @booking.source
        end

        def current_source_label
          label = HotelPortal::BookingSourcePresenter.new(@booking.source).label
          agent = @booking.hotel_corporate_account&.corporate_account&.name if @booking.source == ::Bookings::ChangeSource::TRAVEL_AGENT
          agent ? "#{label} (#{agent})" : label
        end

        # A group is usually booked through one channel, so the whole group is the default.
        def apply_to_group?
          source_params[:apply_to_group].nil? || ActiveModel::Type::Boolean.new.cast(source_params[:apply_to_group])
        end

        def load_travel_agent_accounts
          @travel_agent_accounts = current_hotel.hotel_corporate_accounts.active.where(account_type: "travel_agent")
            .includes(:corporate_account).to_a.sort_by { |relationship| relationship.corporate_account.name.to_s }
        end
      end
    end
  end
end
