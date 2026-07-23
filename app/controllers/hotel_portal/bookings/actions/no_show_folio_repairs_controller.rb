# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based "repair no-show folio". Shows the audited tourism-tax
      # correction preview (GET) and posts the reversal (POST). Single booking
      # only — repair is never a group batch.
      #
      # Business rules live in Bookings::RepairNoShowTourismTax; this controller
      # only orchestrates authorization, input, rendering, and completion.
      class NoShowFolioRepairsController < BaseController
        before_action :authorize_folio_corrections!

        def show
          return create if request.post?

          @tourism_tax_charges = ::Bookings::RepairNoShowTourismTax.eligible_charges_for(@booking)
          @tourism_tax_total = @tourism_tax_charges.sum(&:amount)
          @projected_balances = @tourism_tax_charges.group_by(&:booking_folio).to_h do |folio, charges|
            [ folio, folio.outstanding_balance.to_d - charges.sum(&:amount) ]
          end
          render :show, layout: false
        end

        private

        def create
          result = ::Bookings::RepairNoShowTourismTax.call(booking: @booking, user: current_user)

          if result.success?
            complete_action(notice: repair_notice(result))
          else
            complete_action(alert: result.error)
          end
        end

        def repair_notice(result)
          return "No-show folio already has no tourism tax to repair." if result.reversal_transactions.empty?

          notice = "Tourism tax of #{money(result.repaired_amount)} was removed from the no-show folio."
          return "#{notice} Settled folio closed." if result.closed_folios.any?

          "#{notice} Folio remains open because it has a non-zero balance."
        end

        def money(amount)
          "#{@booking.currency.presence || current_hotel.default_currency} #{format('%.2f', amount)}"
        end

        def authorize_folio_corrections!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("post_folio_corrections", hotel: current_hotel)
        end
      end
    end
  end
end
