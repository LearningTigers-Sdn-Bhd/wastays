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
      night_audit = current_hotel.night_audits.find_or_initialize_by(business_date: requested_business_date)
      if night_audit.completed?
        redirect_to hotel_night_audits_path(current_hotel), alert: "Night audit has already been completed for this date."
        return
      end

      if night_audit.persisted? && %w[pending running].include?(night_audit.status)
        redirect_to hotel_night_audit_path(current_hotel, night_audit), notice: "Night audit is already scheduled or running in the background."
        return
      end

      night_audit.assign_attributes(
        status: "pending",
        trigger_mode: "manual",
        started_at: nil,
        completed_at: nil,
        performed_by_user: current_user,
        notes: params.dig(:night_audit, :notes),
        force_closed: false
      )

      if night_audit.save
        HotelOps::RunNightAuditJob.perform_later(night_audit.id, current_user.id)
        redirect_to hotel_night_audit_path(current_hotel, night_audit), notice: "Night audit has been scheduled in the background. Please wait while it processes."
      else
        redirect_to hotel_night_audits_path(current_hotel), alert: "Night audit could not be created: #{night_audit.errors.full_messages.join(', ')}"
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
