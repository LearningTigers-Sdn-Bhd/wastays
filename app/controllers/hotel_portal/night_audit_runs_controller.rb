# frozen_string_literal: true

module HotelPortal
  class NightAuditRunsController < BaseController
    include SheetActionCompletion

    before_action :authorize_night_audit!
    before_action -> { require_feature!("no_show_auto_handling") }

    def show
      prepare_sheet
      render layout: false if turbo_frame_request?
    end

    def create
      prepare_sheet(sheet_state: :run)
      unless @presenter.ready_to_run?
        flash.now[:alert] = "Continue the steps and complete every item that needs attention before running Night Audit."
        return render :show, layout: false, status: :unprocessable_content
      end

      result = ::NightAudits::Schedule.call(
        hotel: current_hotel,
        business_date: authoritative_business_date,
        performed_by_user: current_user,
        trigger_mode: "manual",
        notes: params.dig(:night_audit_run, :notes),
        allow_unclosable_date: false,
        force_roll: false
      )
      prepare_sheet(sheet_state: :run)
      unless result.enqueued
        flash.now[:alert] = result.error.presence || "The checks changed before Night Audit could start. Complete the items that now need attention."
      end
      render :show, layout: false, status: (result.enqueued ? :accepted : :unprocessable_content)
    rescue ActiveRecord::RecordInvalid => error
      prepare_sheet(sheet_state: :run)
      flash.now[:alert] = "Night audit could not be started: #{error.record.errors.full_messages.to_sentence}"
      render :show, layout: false, status: :unprocessable_content
    end

    def start_review
      result = ::NightAudits::StartManualReview.call(
        hotel: current_hotel,
        business_date: authoritative_business_date,
        actor: current_user
      )
      prepare_sheet
      if result.success?
        flash.now[:notice] = if result.detected_count.positive?
          "Booking checks complete. #{result.due_outs_detected_count} overdue #{'departure'.pluralize(result.due_outs_detected_count)} and #{result.missed_arrivals_detected_count} missed #{'arrival'.pluralize(result.missed_arrivals_detected_count)} need attention."
        else
          "Booking checks complete. No new stays need attention."
        end
      else
        flash.now[:alert] = result.error
      end
      render :show, layout: false, status: (result.success? ? :ok : :unprocessable_content)
    end

    def booking_timestamp
      authorize_booking_management!
      prepare_timestamp_sheet
      render :booking_timestamp, layout: false
    end

    def force_close_confirmation
      authorize_force_close!
      prepare_force_close_sheet
      render :force_close_confirmation, layout: false
    end

    def status
      audit = current_hotel.night_audits.find(params[:audit_id])

      case audit.status
      when "completed"
        flash[:toast] = {
          message: audit.force_closed? ? "Business date force-closed" : "Night audit completed",
          type: "success",
          description: "Business date advanced from #{format_date(audit.business_date)} to #{format_date(audit.business_date + 1.day)}.",
          action: { label: "View details", url: hotel_reports_night_audit_path(current_hotel, audit) }
        }
        render json: { state: "completed", refresh_url: safe_return_to, report_url: hotel_reports_night_audit_path(current_hotel, audit) }
      when "blocked"
        render json: { state: "blocked", sheet_url: hotel_night_audit_run_path(current_hotel, return_to: safe_return_to) }
      when "failed"
        render json: { state: "failed", sheet_url: hotel_night_audit_run_path(current_hotel, return_to: safe_return_to) }
      else
        render json: { state: "processing" }
      end
    end

    def resolve_missing_folio
      resolve_booking_blocker(::NightAudits::ResolveMissingFolio, reason: resolution_reason("Recover missing folio from Night Audit verification"))
    end

    def resolve_missing_nightly_charges
      resolve_booking_blocker(::NightAudits::ResolveMissingNightlyCharges, reason: resolution_reason("Repair nightly charges from Night Audit verification"))
    end

    def resolve_unsynced_payment
      resolve_financial_sync("payment", params.dig(:night_audit_run, :payment_transaction_id))
    end

    def resolve_unsynced_refund
      resolve_financial_sync("refund", params.dig(:night_audit_run, :refund_request_id))
    end

    def resolve_booking_timestamp
      authorize_booking_management!
      prepare_timestamp_sheet
      unless @presenter.review_started?
        flash.now[:alert] = "Continue Night Audit before adding a booking time."
        return render :booking_timestamp, layout: false, status: :unprocessable_content
      end

      result = ::NightAudits::ResolveBookingTimestamp.call(
        night_audit: @night_audit,
        booking: @booking,
        actor: current_user,
        blocker_type: timestamp_blocker_type,
        timestamp: params.dig(:night_audit_run, :timestamp),
        reason: resolution_reason(nil)
      )
      if result.success?
        complete_secondary_action(result.message)
      else
        flash.now[:alert] = result.error
        render :booking_timestamp, layout: false, status: :unprocessable_content
      end
    end

    def resolve_missed_arrival
      authorize_booking_management!
      resolve_booking_blocker(::NightAudits::ResolveMissedArrival, reason: resolution_reason(nil))
    end

    def force_close
      authorize_force_close!
      prepare_force_close_sheet
      reason = params.dig(:night_audit_run, :reason).to_s.strip
      if reason.blank?
        flash.now[:alert] = "A manager reason is required to force-close the business date."
        return render :force_close_confirmation, layout: false, status: :unprocessable_content
      end

      result = ::NightAudits::Schedule.call(
        hotel: current_hotel,
        business_date: authoritative_business_date,
        performed_by_user: current_user,
        trigger_mode: "manual",
        notes: reason,
        allow_unclosable_date: false,
        force_roll: true
      )
      if result.enqueued
        complete_secondary_action("Night Audit is running. The forced close will be permanently recorded.")
      else
        prepare_force_close_sheet
        flash.now[:alert] = result.error.presence || "The business date could not be force-closed. Check the current Night Audit state and try again."
        render :force_close_confirmation, layout: false, status: :unprocessable_content
      end
    end

    private

    def prepare_sheet(sheet_state: nil)
      @business_date = authoritative_business_date
      prepared = ::NightAudits::Prepare.call(hotel: current_hotel, business_date: @business_date)
      @night_audit = prepared.night_audit
      phase = @night_audit&.blocked? ? :post_close : :pre_close
      @evaluation = phase == :pre_close ? prepared.evaluation : ::NightAudits::Evaluate.new(hotel: current_hotel, business_date: @business_date, phase:).call
      detection_failures = Array(@night_audit&.blocked_details.to_h["detection_failures"])
      @evaluation[:blocked_details]["detection_failures"] = detection_failures if detection_failures.any?
      @presenter = HotelPortal::NightAuditRuns::SheetPresenter.new(
        hotel: current_hotel,
        business_date: @business_date,
        evaluation: @evaluation,
        night_audit: @night_audit
      )
      @return_to = safe_return_to
      @sheet_state = sheet_state || (resume_run_sheet? ? :run : :confirmation)
      @confirmation = @sheet_state == :confirmation
    end

    def prepare_timestamp_sheet
      prepare_sheet(sheet_state: :run)
      attributes = params[:night_audit_run].presence || params
      @booking = current_hotel.bookings.find(attributes[:booking_id])
      @timestamp_kind = normalized_timestamp_kind(attributes[:timestamp_kind])
      @parent_frame = params[:parent_frame].presence || "booking_action_sheet"
    end

    def prepare_force_close_sheet
      prepare_sheet(sheet_state: :run)
      @parent_frame = params[:parent_frame].presence || "booking_action_sheet"
    end

    def resolve_booking_blocker(service, reason:)
      prepare_sheet
      return unless ensure_review_started!

      booking = current_hotel.bookings.find(params.dig(:night_audit_run, :booking_id))
      result = service.call(night_audit: @night_audit, booking:, actor: current_user, reason:)
      render_resolution(result, success_message: result.message)
    end

    def resolve_financial_sync(kind, item_id)
      prepare_sheet
      return unless ensure_review_started!

      booking = current_hotel.bookings.find(params.dig(:night_audit_run, :booking_id))
      result = ::NightAudits::ResolveFinancialSync.call(
        night_audit: @night_audit,
        booking:,
        actor: current_user,
        kind:,
        item_id:,
        reason: resolution_reason(nil)
      )
      render_resolution(result, success_message: result.message)
    end

    def render_resolution(result, success_message:)
      prepare_sheet(sheet_state: :run)
      flash.now[result.success? ? :notice : :alert] = result.success? ? success_message : result.error
      render :show, layout: false, status: (result.success? ? :ok : :unprocessable_content)
    end

    def resolution_reason(fallback)
      params.dig(:night_audit_run, :reason).to_s.strip.presence || fallback
    end

    def ensure_review_started!
      return true if @presenter.review_started?

      flash.now[:alert] = "Continue Night Audit before working on items that need attention."
      render :show, layout: false, status: :unprocessable_content
      false
    end

    def resume_run_sheet?
      @presenter.review_started? || @night_audit&.status.in?(%w[pending running blocked failed])
    end

    def normalized_timestamp_kind(value)
      value.to_s == "check_out" ? "check_out" : "check_in"
    end

    def timestamp_blocker_type
      @timestamp_kind == "check_out" ? "completed_missing_timestamp" : "checked_in_missing_timestamp"
    end

    def complete_secondary_action(notice)
      complete_sheet_action(
        destination: @return_to,
        notice: notice,
        frame: turbo_frame_request_id.presence || "booking_action_sheet_secondary"
      )
    end

    def authoritative_business_date
      current_hotel.current_business_date ||
        HotelBusinessDate.initialize_for_hotel!(hotel: current_hotel, date: current_hotel.business_date_for(Time.current)).business_date
    end

    def safe_return_to
      candidate = params[:return_to].presence || request.referer
      return hotel_front_desk_path(current_hotel) if candidate.blank?

      uri = URI.parse(candidate)
      return hotel_front_desk_path(current_hotel) if uri.host.present? && "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}" != request.base_url
      path = uri.host.present? ? uri.request_uri : uri.to_s
      path.start_with?("/hotel/#{current_hotel.to_param}/") ? path : hotel_front_desk_path(current_hotel)
    rescue URI::InvalidURIError
      hotel_front_desk_path(current_hotel)
    end

    def unclosable_date_message
      window = current_hotel.business_day_window_for(@business_date)
      "Business date #{format_date(@business_date)} cannot be audited yet. The business day ends at #{window.end.strftime('%I:%M %p')}."
    end

    def format_date(date) = date.strftime("%d %b %Y")

    def authorize_night_audit!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_night_audit", hotel: current_hotel)
    end

    def authorize_booking_management!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
    end

    def authorize_force_close!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("override_financial_date_lock", hotel: current_hotel)
    end
  end
end
