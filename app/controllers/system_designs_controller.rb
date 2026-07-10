# frozen_string_literal: true

# Living showcase for the PanelsUI primitive component library. It uses a dedicated
# layout so the real Tailwind and importmap assets are present without application
# navigation, widgets, or footer chrome. Not exposed in production (see routes.rb).
class SystemDesignsController < ApplicationController
  layout "system_design"

  def index
    @reservation_request = SystemDesigns::ReservationRequest.new
  end

  # Backs the form-submission preview. Turbo targets the form frame, so a valid
  # request swaps in a fresh form (200) and an invalid one re-renders with inline
  # errors (422). The Stimulus controller keys its result toast off that status.
  def submit_form
    reservation = SystemDesigns::ReservationRequest.new(reservation_params)

    if reservation.valid?
      render partial: "system_designs/reservation_form",
             locals: { reservation: SystemDesigns::ReservationRequest.new, state: :saved }
    else
      render partial: "system_designs/reservation_form",
             locals: { reservation: reservation, state: :invalid },
             status: :unprocessable_entity
    end
  end

  private

  def reservation_params
    params.fetch(:reservation_request, {}).permit(:guest_name, :email, :nights)
  end
end
