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

        helper_method :checkout_sheet_presenter, :checkout_early_checkout_lines, :checkout_penalty_folio_id, :checkout_form_state,
          :checkout_deposits, :checkout_deposit_action_path, :checkout_deposit_blocking?, :checkout_deposit_available_amount

        def show
          return complete if request.post?

          render :show, layout: false
        end

        def folio_status
          bookings = checkout_status_bookings
          render json: {
            folios: bookings.flat_map do |booking|
              checkout_sheet_presenter(booking).folio_rows.map do |row|
                adjustment = checkout_status_adjustment(booking, row.folio)
                balance = row.balance.to_d + adjustment
                {
                  booking_id: booking.id,
                  folio_id: row.folio.id,
                  balance: balance.to_s("F"),
                  status: row.folio.status,
                  payment_url: checkout_settlement_url(booking, row.folio, "payment", balance, adjustment),
                  refund_url: checkout_settlement_url(booking, row.folio, "refund", balance, adjustment)
                }
              end
            end,
            deposits: checkout_deposits(bookings).map { |deposit| checkout_deposit_status(deposit, bookings) }
          }
        end

        private

        def complete
          timestamp = checkout_timestamp
          return render_checkout_error("Check-out date and time can't be blank.") if @booking.checkout_required? && timestamp.blank?

          targets = checkout_targets
          unresolved = checkout_deposits(targets).find do |deposit|
            checkout_deposit_blocking?(deposit, targets) && deposit.available_amount.positive?
          end
          if unresolved
            return render_checkout_error("Resolve the remaining #{unresolved.currency} #{format('%.2f', unresolved.available_amount)} deposit balance before checkout.")
          end

          error = nil
          completed = []
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
          Notifications::InvoiceDelivery.queue(
            hotel: current_hotel,
            bookings: completed,
            anchor_booking: @booking,
            source: "automatic_checkout"
          )
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
            security_deposit_options: {}
          )
        end

        def checkout_targets
          return [ @booking ] unless selected_lifecycle_batch?(@booking)

          selected_lifecycle_bookings(fallback_booking: @booking, action: :checkout)
        end

        def checkout_status_bookings
          return [ @booking ] unless @booking.group_booking_id.present?

          ids = Array(params[:booking_ids]).reject(&:blank?).map(&:to_i).uniq
          if ids.any?
            bookings = @booking.group_booking.bookings.includes(:booking_folio).where(id: ids).order(:group_position, :id).to_a
            raise BatchTargetError, "One or more selected bookings are not part of this group." unless bookings.size == ids.size
            return bookings
          end

          presenter = HotelPortal::BookingLifecycleTargetPresenter.new(booking: @booking, action: :checkout)
          presenter.rows.select(&:eligible).map(&:booking).presence || [ @booking ]
        end

        def checkout_status_adjustment(booking, folio)
          values = params.dig(:early_departures, booking.id.to_s)
          early_departure = if values.present? && checkout_penalty_folio_id(booking).to_i == folio.id
            calculated_early_departure_charge(booking, values)
          else
            0.to_d
          end
          early_departure
        end

        def checkout_settlement_url(booking, folio, kind, balance, adjustment)
          token = ::Checkouts::SettlementToken.issue(
            booking: booking,
            folio: folio,
            kind: kind,
            amount: balance,
            adjustment: adjustment
          )
          hotel_folio_action_post_transaction_path(
            current_hotel,
            booking,
            transaction_type: "payment",
            category: ("refund" if kind == "refund"),
            settlement_token: token,
            return_to: hotel_booking_action_checkout_path(current_hotel, booking)
          )
        end

        def checkout_timestamp
          params[:checked_out_at].presence || params.dig(:booking, :checked_out_at).presence
        end

        def early_departure_params_for(booking)
          scoped = params.dig(:early_departures, booking.id.to_s) || params.dig(:early_departures, booking.id)
          return params.permit(:apply_charge, :charge_amount).to_h.symbolize_keys if scoped.blank?

          permitted = scoped.respond_to?(:to_unsafe_h) ? scoped.to_unsafe_h : scoped.to_h
          {
            apply_charge: permitted["apply_charge"],
            charge_amount: calculated_early_departure_charge(booking, permitted)
          }
        end

        def calculated_early_departure_charge(booking, values)
          values = values.to_unsafe_h if values.respond_to?(:to_unsafe_h)
          values = values.to_h.with_indifferent_access
          return 0.to_d unless ActiveModel::Type::Boolean.new.cast(values[:apply_charge])

          input = values[:value].to_d
          return input unless values[:type] == "percentage"

          nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
          base = nights.positive? ? booking.total_amount.to_d / nights : 0.to_d
          (base * input / 100).round(2)
        end

        def checkout_folio_action_params(booking)
          scoped = params.dig(:checkout_bookings, booking.id.to_s, :folios) || params.dig(:checkout_bookings, booking.id, :folios)
          raw_params = scoped.presence || params[:checkout_folios]
          return default_checkout_folio_action_params(booking) if raw_params.blank?

          permitted = raw_params.respond_to?(:to_unsafe_h) ? raw_params.to_unsafe_h : raw_params.to_h
          permitted.transform_values do |value|
            value.to_h.slice("action", "amount", "payment_method", "payment_reference", "reason", "credit_override", "credit_override_reason")
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

        def checkout_deposits(bookings)
          ids = Array(bookings).map(&:id)
          booking_scope = current_hotel.deposits.where(booking_id: ids)
          group_ids = Array(bookings).map(&:group_booking_id).compact.uniq
          scope = if group_ids.one?
            booking_scope.or(current_hotel.deposits.where(group_booking_id: group_ids.first))
          else
            booking_scope
          end
          scope.includes(:deposit_movements, :booking, :group_booking, :transaction_code).order(:received_at, :id).to_a
        end

        def checkout_deposit_blocking?(deposit, bookings)
          return false unless deposit.status.in?(%w[held available])
          return Array(bookings).map(&:id).include?(deposit.booking_id) if deposit.booking_id.present?

          final_group_checkout?(bookings) && deposit.group_booking_id == common_checkout_group(bookings)&.id
        end

        def checkout_deposit_status(deposit, bookings)
          {
            deposit_id: deposit.id,
            status: deposit.status,
            applied_amount: deposit.applied_amount.to_d.to_s("F"),
            returned_amount: deposit.returned_amount.to_d.to_s("F"),
            available_amount: checkout_deposit_available_amount(deposit).to_s("F"),
            blocking: checkout_deposit_blocking?(deposit, bookings)
          }
        end

        def checkout_deposit_available_amount(deposit)
          deposit.status.in?(%w[held available]) ? deposit.available_amount : 0.to_d
        end

        def checkout_deposit_action_path(deposit, operation, bookings)
          hotel_booking_action_checkout_deposit_settlement_path(
            current_hotel,
            @booking,
            deposit,
            operation: operation,
            booking_ids: Array(bookings).map(&:id),
            return_to: hotel_booking_action_checkout_path(current_hotel, @booking)
          )
        end

        def final_group_checkout?(bookings)
          group = common_checkout_group(bookings)
          group.present? && group.bookings.where.not(id: Array(bookings).map(&:id)).where.not(status: %w[completed cancelled]).none?
        end

        def common_checkout_group(bookings)
          ids = Array(bookings).map(&:group_booking_id).compact.uniq
          ids.one? ? current_hotel.group_bookings.find(ids.first) : nil
        end

        # Memoised presenter + routed early-checkout preview per booking, shared
        # between the view and the fallback params.
        def checkout_sheet_presenter(booking)
          (@checkout_sheet_presenters ||= {})[booking.id] ||= HotelPortal::Bookings::Actions::Checkouts::SheetPresenter.new(
            booking: booking,
            hotel: current_hotel,
            user: current_user,
            early_checkout_lines: checkout_early_checkout_lines(booking),
            early_checkout: current_hotel.current_business_date < booking.check_out.to_date
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
