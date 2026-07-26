# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Staged billing-route editor for every child in a group booking.
      class GroupBillingRoutesController < BaseController
        def show
          return dispatch_workflow if request.post?

          prepare_group_billing_routes
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_movements")
        end

        def set_return_to
          @return_to = folio_action_return_to(
            fallback: hotel_booking_workspace_path(current_hotel, @booking, tab: "billing_preferences", scope: "group")
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
          prepare_group_billing_routes
          @group_route_draft = group_billing_routes_params
          @group_batch_preview = ::Folios::Routing::ApplyGroupBatch.preview(
            group_booking: @group,
            booking_routes: @group_route_draft
          )
          return apply if @group_batch_preview.success? && !@group_batch_preview.review_required?

          flash.now[:alert] = @group_batch_preview.error unless @group_batch_preview.success?
          render :show, layout: false, status: (@group_batch_preview.success? ? :ok : :unprocessable_content)
        end

        def apply
          prepare_group_billing_routes
          result = ::Folios::Routing::ApplyGroupBatch.call(
            group_booking: @group,
            actor: current_user,
            booking_routes: group_billing_routes_params,
            confirmation: params[:confirmation],
            forecast_confirmation: params[:forecast_confirmation],
            reason: params[:reason],
            idempotency_key: params[:idempotency_key]
          )
          return complete_action(notice: "Group billing routes updated.") if result.success?

          @group_route_draft = group_billing_routes_params
          @group_batch_preview = ::Folios::Routing::ApplyGroupBatch.preview(
            group_booking: @group,
            booking_routes: @group_route_draft
          )
          flash.now[:alert] = result.error
          render :show, layout: false, status: :unprocessable_content
        end

        def render_invalid_workflow
          prepare_group_billing_routes
          flash.now[:alert] = "Select a valid group billing-route action."
          render :show, layout: false, status: :unprocessable_content
        end

        def prepare_group_billing_routes
          @group = group_booking
          @group_bookings = @group.bookings.includes(
            :booking_rooms,
            :booking_guests,
            { booking_folios: :booking_billing_party },
            { folio_routing_rules: :target_folio }
          )
          @group_readiness = ::Folios::Routing::GroupRoutingReadiness.new(group_booking: @group)
          @group_batch_key = params[:idempotency_key].presence || SecureRandom.uuid
        end

        def group_booking
          raise ActiveRecord::RecordNotFound unless @booking.group_booking_id.present?

          @group_booking ||= current_hotel.group_bookings.find(@booking.group_booking_id)
        end

        def group_billing_routes_params
          params.permit(group_routes: {}).fetch(:group_routes, {}).to_h
        end
      end
    end
  end
end
