# frozen_string_literal: true

module HotelPortal
  class TrainingDecisionsController < BaseController
    before_action :authorize_training_decision!

    def keep
      result = Onboarding::CompleteTraining.call(hotel: current_hotel, actor: current_user, decision: "keep")
      redirect_with_result(result, success: "Your property is now live with your current PMS data.")
    end

    def reset
      result = Onboarding::RequestTrainingReset.call(hotel: current_hotel, actor: current_user)
      redirect_with_result(result, success: "We’re clearing your PMS activity. The PMS will remain read-only until it finishes.")
    end

    private

    def authorize_training_decision!
      authorize current_hotel, :update?
    end

    def redirect_with_result(result, success:)
      redirect_to hotel_dashboard_path(current_hotel),
                  notice: (success if result.success?),
                  alert: (result.error unless result.success?),
                  status: :see_other
    end
  end
end
