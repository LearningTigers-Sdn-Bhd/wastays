# frozen_string_literal: true

module HotelPortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "hotel"
    before_action :authenticate_user!
    before_action :reject_corporate_user!
    before_action :ensure_hotel_access!

    helper_method :locked_hotel_portal_shell?

    private

    def reject_corporate_user!
      return unless current_user&.corporate?

      redirect_to corporate_dashboard_path, alert: "Corporate users do not have hotel staff access."
    end

    def locked_hotel_portal_shell?
      current_hotel.present? && (current_hotel.onboarding? || current_hotel.status == "pending_review")
    end
  end
end
