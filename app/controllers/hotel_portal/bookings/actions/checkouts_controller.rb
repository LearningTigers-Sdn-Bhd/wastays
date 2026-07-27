# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based checkout settlement. Renders the folio-settlement form (GET)
      # and completes checkout (POST) for single or group targets, coordinating
      # early departure, per-folio settlement actions, checkout-required audit
      # blockers, and security-deposit release.
      #
      # Business rules live in Checkouts::ProcessBookingCheckout (and the folios
      # services it calls); this controller only orchestrates authorization,
      # input, rendering, and completion.
      class CheckoutsController < BaseController
        include GroupLifecycleTargeting

        helper_method :checkout_sheet_presenter, :checkout_early_checkout_lines, :checkout_penalty_folio_id, :checkout_form_state

        def show
          return complete if request.post?

          render :show, layout: false
        end

        private

        def complete
          timestamp = checkout_timestamp
          return render_checkout_error("Check-out date and time can't be blank.") if @booking.checkout_required? && timestamp.blank?

          error = nil
          completed = []
          targets = checkout_targets

          ActiveRecord::Base.transaction do
            targets.each do |booking|
              result = process_checkout_for_booking(booking, timestamp)
              unless result.success?
                error = targets.one? ? result.error : "#{checkout_booking_label(booking)}: #{result.error}"
                raise ActiveRecord::Rollback
              end
              completed << booking
            end
          end

          return render_checkout_error(error) if error.present?

          completed.each { |booking| dispatch_checkout_side_effects(booking) }
          notice = completed.one? ? "Guest has been checked out." : "#{completed.size} bookings checked out."
          complete_booking_action(destination: checkout_success_path, notice: notice, frame: requesting_sheet_frame)
        rescue BatchTargetError => e
          render_checkout_error(e.message)
        end

        def process_checkout_for_booking(booking, timestamp)
          ::Checkouts::ProcessBookingCheckout.call(
            booking: booking,
            hotel: current_hotel,
            user: current_user,
            timestamp: timestamp,
            folio_action_params: checkout_folio_action_params(booking),
            posting_date: current_hotel.current_business_date,
            early_departure_params: early_departure_params_for(booking),
            checkout_options: checkout_blocker_resolution_options(booking),
            security_deposit_options: security_deposit_release_options
          )
        end

        def checkout_targets
          return [ @booking ] unless selected_lifecycle_batch?(@booking)

          selected_lifecycle_bookings(fallback_booking: @booking, action: :checkout)
        end

        def checkout_timestamp
          params[:checked_out_at].presence || params.dig(:booking, :checked_out_at).presence
        end

        def early_departure_params_for(booking)
          scoped = params.dig(:early_departures, booking.id.to_s) || params.dig(:early_departures, booking.id)
          return params.permit(:apply_charge, :charge_amount).to_h.symbolize_keys if scoped.blank?

          permitted = scoped.respond_to?(:to_unsafe_h) ? scoped.to_unsafe_h : scoped.to_h
          { apply_charge: permitted["apply_charge"], charge_amount: permitted["charge_amount"] }
        end

        def checkout_folio_action_params(booking)
          scoped = params.dig(:checkout_bookings, booking.id.to_s, :folios) || params.dig(:checkout_bookings, booking.id, :folios)
          raw_params = scoped.presence || params[:checkout_folios]
          return default_checkout_folio_action_params(booking) if raw_params.blank?

          permitted = raw_params.respond_to?(:to_unsafe_h) ? raw_params.to_unsafe_h : raw_params.to_h
          permitted.transform_values do |value|
            value.to_h.slice("action", "amount", "payment_method", "payment_reference", "reason")
          end
        end

        # Fallback folio actions when the form omits them. Includes the routed
        # early-checkout preview so pay-now amounts match the post-early-departure
        # balance (fixes the amount mismatch on the fallback path).
        def default_checkout_folio_action_params(booking)
          checkout_sheet_presenter(booking).folio_rows.each_with_object({}) do |row, actions|
            actions[row.folio.id.to_s] = {
              "action" => row.default_action,
              "amount" => format("%.2f", row.balance.to_d)
            }
          end
        end

        def checkout_blocker_resolution_options(booking)
          return {} unless booking.checkout_required?
          return {} unless current_hotel.current_business_date_record&.audit_blocked?

          audit = current_hotel.night_audits.where(business_date: current_hotel.current_business_date).order(created_at: :desc).first
          return {} unless audit

          {
            posting_source: "audit_blocker_resolution",
            correction_reason: "Resolve checkout-required night audit blocker",
            blocker_resolution: {
              night_audit_id: audit.id,
              blocker_type: "due_out_not_checked_out",
              booking_id: booking.id
            }
          }
        end

        def security_deposit_release_options
          return {} unless params[:release_security_deposit] == "1"

          {
            security_deposit_release: {
              method: params[:security_deposit_release_method].to_s.presence || "cash",
              reference: params[:security_deposit_release_reference].to_s.strip.presence
            }
          }
        end

        # Memoised presenter + routed early-checkout preview per booking, shared
        # between the view and the fallback params.
        def checkout_sheet_presenter(booking)
          (@checkout_sheet_presenters ||= {})[booking.id] ||= HotelPortal::Bookings::Actions::Checkouts::SheetPresenter.new(
            booking: booking,
            hotel: current_hotel,
            user: current_user,
            early_checkout_lines: checkout_early_checkout_lines(booking)
          )
        end

        def checkout_form_state(bookings:, sheets:)
          @checkout_form_state ||= HotelPortal::Bookings::Actions::Checkouts::FormState.new(
            anchor_booking: @booking,
            bookings: bookings,
            sheets: sheets,
            checked_out_at_default: @presenter.checked_out_at_form_value,
            params: params,
            submitted: request.post?,
            group: @booking.group_booking_id.present?
          )
        end

        def checkout_early_checkout_lines(booking)
          (@checkout_early_lines ||= {})[booking.id] ||= begin
            folio = booking.booking_folio
            business_date = current_hotel.current_business_date
            if folio && business_date < booking.check_out.to_date
              ::Folios::Charges::PostEarlyCheckoutCharges.pending_preview(
                booking: booking,
                folio: folio,
                departure_date: business_date,
                original_check_out: booking.check_out
              )
            else
              []
            end
          end
        end

        # Folio the manual early-departure penalty routes to (room_revenue route),
        # so the settlement JS folds the live charge into the right folio's amount.
        def checkout_penalty_folio_id(booking)
          route = ::Folios::Routing::ResolveTargetFolio.call(
            booking: booking,
            transaction_code: ::TransactionCodes::Resolver.for(current_hotel).room_revenue
          )
          route.success? ? route.folio&.id : booking.booking_folio&.id
        end

        def checkout_booking_label(booking)
          room = booking.booking_rooms.first
          room_type = room&.room_type&.name.presence || room&.room_type_snapshot.to_h["name"].presence || "Room type unavailable"
          room_number = room&.room_number.presence || "Unassigned room"
          number = booking.formatted_reservation_number.presence || booking.confirmation_token.presence || booking.id
          "Booking ##{number} / #{room_type} - #{room_number}"
        end

        def dispatch_checkout_side_effects(booking)
          ::Bookings::WebhookTriggerService.new(booking).trigger(:booking_completed)
          ::Notifications::Dispatcher.new(event: :booking_completed, booking: booking).call
          SendInvoiceEmailJob.perform_later(booking.id)
        end

        def checkout_success_path
          booking_action_return_to(fallback: hotel_booking_workspace_path(current_hotel, @booking, tab: "booking_details", checkout_success: true))
        end

        def render_checkout_error(error)
          @checkout_error = error
          respond_to do |format|
            format.turbo_stream do
              flash.now[:alert] = error
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/checkouts/form",
                locals: { booking: @booking, checkout_error: error }
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end

        def set_booking
          @booking = current_hotel.bookings
                                  .includes(
                                    :deposits,
                                    booking_folios: [ :hotel, :folio_forecasted_charges, { folio_transactions: :user }, { hotel_corporate_account: :corporate_account } ]
                                  )
                                  .find(params[:booking_id])
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        end
      end
    end
  end
end
