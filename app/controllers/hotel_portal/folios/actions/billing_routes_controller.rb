# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Staged selective billing-route editor for one booking. A POST previews
      # or applies the submitted routing matrix according to `workflow_step`.
      class BillingRoutesController < BaseController
        def show
          return dispatch_workflow if request.post?

          prepare_billing_routes
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_movements")
        end

        def set_return_to
          @return_to = folio_action_return_to(
            fallback: hotel_booking_workspace_path(current_hotel, routing_booking, tab: "billing_preferences")
          )
        end

        def dispatch_workflow
          case params[:workflow_step]
          when "preview" then preview
          when "apply" then apply
          else render_invalid_workflow
          end
        end

        def preview
          prepare_billing_routes
          @route_draft = billing_routes_params
          @batch_preview = ::Folios::Routing::ApplyBatch.preview(booking: @routing_booking, routes: @route_draft)
          return apply if @batch_preview.success? && !@batch_preview.review_required?

          flash.now[:alert] = @batch_preview.error unless @batch_preview.success?
          render :show, layout: false, status: (@batch_preview.success? ? :ok : :unprocessable_content)
        end

        def apply
          prepare_billing_routes
          result = ::Folios::Routing::ApplyBatch.call(
            booking: @routing_booking,
            actor: current_user,
            routes: billing_routes_params,
            confirmation: params[:confirmation],
            forecast_confirmation: params[:forecast_confirmation],
            reason: params[:reason],
            idempotency_key: params[:idempotency_key]
          )
          return complete_action(notice: "Billing routes updated.") if result.success?

          @route_draft = billing_routes_params
          @batch_preview = ::Folios::Routing::ApplyBatch.preview(booking: @routing_booking, routes: @route_draft)
          flash.now[:alert] = result.error
          render :show, layout: false, status: :unprocessable_content
        end

        def render_invalid_workflow
          prepare_billing_routes
          flash.now[:alert] = "Select a valid billing-route action."
          render :show, layout: false, status: :unprocessable_content
        end

        def prepare_billing_routes
          @routing_booking = routing_booking
          @routing_booking_options = routing_booking_options
          @routing_matrix = ::Folios::Routing::RoutingMatrix.new(booking: @routing_booking)
          @batch_key = params[:idempotency_key].presence || SecureRandom.uuid
        end

        def routing_booking
          return @routing_booking if defined?(@routing_booking) && @routing_booking.present?
          return @booking unless @booking.group_booking_id?

          selected_id = params[:route_booking_id].presence || @booking.id
          current_hotel.bookings.where(group_booking_id: @booking.group_booking_id).find(selected_id)
        end

        def routing_booking_options
          return [] unless @booking.group_booking_id?

          current_hotel.bookings
                       .where(group_booking_id: @booking.group_booking_id)
                       .includes(:booking_rooms, :booking_guests)
                       .order(:group_position, :id)
        end

        def billing_routes_params
          params.permit(routes: {}).fetch(:routes, {}).to_h
        end
      end
    end
  end
end
