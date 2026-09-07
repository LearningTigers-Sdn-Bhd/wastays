# frozen_string_literal: true

# Living showcase for the PanelsUI primitive component library. It uses a dedicated
# layout so the real Tailwind and importmap assets are present without application
# navigation, widgets, or footer chrome. Not exposed in production (see routes.rb).
class SystemDesignsController < ApplicationController
  layout "system_design"

  def index
    @previews = SystemDesigns::Previews::ALL
    @previews = @previews.select { |preview| requested_partials.include?(preview[:partial]) } if params[:only].present?
    set_pagination_previews if @previews.any? { |preview| preview[:partial] == "pagination_preview" }
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
             status: :unprocessable_content
    end
  end

  # Harmless endpoint used by the showcase to exercise Turbo's real asynchronous
  # form-confirm contract without mutating application data.
  def confirm_alert_dialog
    redirect_to system_design_path(turbo_confirmed: "1", anchor: "turbo-confirmed")
  end

  private

  def requested_partials
    params[:only].to_s.split(",")
  end

  def set_pagination_previews
    @pagination_preview, = pagy(
      :offset,
      (1..250).to_a,
      page: preview_page(params[:pagination_page], default: 6),
      page_key: "pagination_page",
      limit: 25
    )
    @single_page_preview, = pagy(:offset, [ 1 ], page_key: "single_page", limit: 25)
  end

  # The preview accepts a page from the URL, so a zero or a word must not raise.
  def preview_page(value, default:)
    page = value.to_i
    page.positive? ? page : default
  end

  def reservation_params
    params.fetch(:reservation_request, {}).permit(:guest_name, :email, :nights)
  end
end
