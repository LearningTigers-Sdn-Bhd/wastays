# frozen_string_literal: true

module HotelPortal
  class OnboardingSubmissionsController < BaseController
    layout "onboarding"

    def create
      authorize current_hotel, :update?, policy_class: HotelPolicy
      result = Onboarding::SubmitOnboarding.call(
        hotel: current_hotel,
        actor: current_user,
        idempotency_key: params[:idempotency_key]
      )

      if result.success?
        redirect_to hotel_onboarding_section_path(current_hotel, section_key: "review"),
                    notice: "Property setup submitted for review."
      else
        redirect_to hotel_onboarding_section_path(current_hotel, section_key: "review"), alert: result.error
      end
    end
  end
end
