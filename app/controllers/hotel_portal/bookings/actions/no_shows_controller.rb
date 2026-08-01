# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based "mark as no-show". Renders the confirmation form into the
      # requesting Sheet frame (GET) and finalizes the no-show (POST), supporting
      # single and group batch targeting.
      #
      # Business rules live in Bookings::FinalizeNoShow; this controller only
      # orchestrates authorization, input, rendering, and completion.
      class NoShowsController < BaseController
        include GroupLifecycleTargeting

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          unless selected_lifecycle_batch?(@booking) || @booking.status == "no_show_detected"
            return complete_action(alert: "Booking is not pending no-show review.")
          end

          if no_show_reason.blank?
            @booking.errors.add(:base, "No-show reason is required.")
            return render_no_show_failure
          end

          return batch_mark_no_show if selected_lifecycle_batch?(@booking)

          result = finalize(@booking)

          if result.success?
            complete_action(notice: no_show_notice(result))
          else
            complete_action(alert: result.error)
          end
        end

        def batch_mark_no_show
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :mark_no_show)

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = finalize(booking)
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_action(notice: batch_lifecycle_notice(bookings, "marked as no-show"))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        def finalize(booking)
          ::Bookings::FinalizeNoShow.call(booking: booking, user: current_user, reason: no_show_reason)
        end

        def no_show_notice(result)
          notice = "Booking marked as no-show. Tourism tax was not charged."
          return "#{notice} Settled folio closed." if result.closed_folios.any?
          return notice if result.skipped_folios.empty?

          balances = result.skipped_folios.map do |entry|
            "#{entry.folio.display_name}: #{entry.folio.currency} #{format('%.2f', entry.balance)}"
          end
          "#{notice} Folio remains open (#{balances.to_sentence})."
        end

        def no_show_reason
          params[:no_show_reason].to_s.strip
        end

        def render_no_show_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/no_shows/form",
                locals: { booking: @booking }
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
