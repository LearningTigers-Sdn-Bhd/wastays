# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The sheet that writes the guest note on one reservation policy.
    #
    # The charge belongs to Room Revenue and stays there. Only the note is
    # editable here, because the note is prose for guests and this is the page
    # that owns guest content.
    #
    # The lookup takes active policies only. An off policy posts nothing, so a
    # note on it would explain a charge that never happens.
    class PolicyReservationNotesController < HotelPortal::GuestContent::BaseController
      include SheetActionCompletion

      before_action :set_policy

      def edit
        render layout: false
      end

      def update
        result = ::ReservationPolicies::Save.call(policy: @policy, attributes: note_params)

        if result.success?
          complete_sheet_action(
            destination: hotel_policy_reservations_path(@hotel),
            notice: "#{@policy.policy_type_label} note saved.",
            frame: sheet_frame
          )
        else
          render :edit, layout: false, status: :unprocessable_content
        end
      end

      private

      def set_policy
        @policy = @hotel.hotel_reservation_policies.charging.find(params[:id])
      end

      # Only the note. A charge changed from here would make Room Revenue and
      # this page mean different things.
      def note_params
        params.require(:hotel_reservation_policy).permit(:description)
      end

      def sheet_frame
        turbo_frame_request_id.presence || "settings_action_sheet"
      end
    end
  end
end
