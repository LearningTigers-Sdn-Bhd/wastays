module HotelPortal
  class NightAuditsController < BaseController
    before_action :authorize_night_audit_access!

    def index
      @suggested_business_date = current_hotel.latest_closable_business_date
      @night_audits = current_hotel.night_audits.recent_first.page(params[:page]).per(25)
      @pre_audit_evaluation = HotelOps::EvaluateNightAudit.new(hotel: current_hotel, business_date: @suggested_business_date).call
    end

    def show
      @night_audit = current_hotel.night_audits.find(params[:id])
    end

    def create
      result = HotelOps::RunNightAudit.new(
        hotel: current_hotel,
        business_date: requested_business_date,
        performed_by_user: current_user,
        trigger_mode: "manual",
        notes: params.dig(:night_audit, :notes)
      ).call

      if result.night_audit.present?
        flash[result.success? ? :notice : :alert] = result.success? ? "Night audit completed successfully." : (result.error || "Night audit completed with blockers.")
        redirect_to hotel_night_audit_path(current_hotel, result.night_audit)
      else
        redirect_to hotel_night_audits_path(current_hotel), alert: result.error || "Night audit could not be created."
      end
    end

    private

    def authorize_night_audit_access!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_night_audit", hotel: current_hotel)
    end

    def requested_business_date
      raw_value = params.dig(:night_audit, :business_date)
      raw_value.present? ? Date.parse(raw_value) : current_hotel.latest_closable_business_date
    rescue ArgumentError, TypeError
      current_hotel.latest_closable_business_date
    end
  end
end
