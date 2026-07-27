module HotelPortal
  class NightAuditsController < BaseController
    INDEX_TAB_LABELS = {
      "audit-history" => "Audit History",
      "advanced-actions" => "Advanced Actions"
    }.freeze
    SHOW_TAB_LABELS = {
      "results" => "Results",
      "financial-summary" => "Financial Summary",
      "advanced-actions" => "Advanced Actions"
    }.freeze

    before_action :authorize_night_audit_access!
    before_action -> { require_feature!("no_show_auto_handling") }

    def index
      @active_tab = selected_tab(INDEX_TAB_LABELS, default: "audit-history")
      append_breadcrumb({ label: INDEX_TAB_LABELS.fetch(@active_tab), tab_label: true, tabs_id: "night-audit-index-tabs" })
      @suggested_business_date = authoritative_business_date
      @night_audits = current_hotel.night_audits.recent_first.page(params[:page]).per(25)
      @pre_audit_evaluation = ::NightAudits::Evaluate.new(hotel: current_hotel, business_date: @suggested_business_date).call
      @presenter = HotelPortal::NightAudits::IndexPresenter.new(
        hotel: current_hotel,
        current_user: current_user,
        business_date_record: current_hotel.current_business_date_record,
        evaluation: @pre_audit_evaluation,
        night_audits: @night_audits
      )
    end

    def show
      @night_audit = current_hotel.night_audits.find(params[:id])
      @active_tab = selected_tab(SHOW_TAB_LABELS, default: "results")
      append_breadcrumb @night_audit.business_date.strftime("%d %b %Y"), hotel_night_audit_path(current_hotel, @night_audit)
      append_breadcrumb({ label: SHOW_TAB_LABELS.fetch(@active_tab), tab_label: true, tabs_id: "night-audit-show-tabs" })

      @adjustments = FolioTransaction.joins(booking_folio: :booking)
        .where(bookings: { hotel_id: current_hotel.id })
        .where(category: [ "adjustment", "discount", "correction", "write_off" ])
        .where(created_at: current_hotel.business_day_window_for(@night_audit.business_date))
        .includes(:user, booking_folio: :booking)
        .order(:created_at)
      @completed_nightly_review = if @night_audit.completed?
        ::NightAudits::CompletedNightlyChargeReview.call(night_audit: @night_audit)
      else
        []
      end

      respond_to do |format|
        format.html do
          @presenter = HotelPortal::NightAudits::ShowPresenter.new(
            night_audit: @night_audit,
            adjustments: @adjustments,
            completed_nightly_review: @completed_nightly_review,
            current_user: current_user,
            view_context: view_context
          )
        end
        format.pdf do
          pdf_content = ::NightAudits::AuditPacketPdfExport.new(night_audit: @night_audit).generate
          filename = "Audit_Packet_#{current_hotel.name.gsub(/\s+/, "_")}_#{@night_audit.business_date}.pdf"
          send_data pdf_content, filename: filename, type: "application/pdf", disposition: "inline"
        end
      end
    end

    def resolve
      @night_audit = current_hotel.night_audits.find(params[:id])
      redirect_to hotel_night_audit_path(current_hotel, @night_audit), alert: "Night audit is not blocked." unless @night_audit.blocked?
    end

    def blockers
      @night_audit = current_hotel.night_audits.find(params[:id])
      result = ::NightAudits::Evaluate.new(
        hotel: current_hotel,
        business_date: @night_audit.business_date
      ).call

      render json: {
        blocked_details: result[:blocked_details],
        exceptions: result[:exceptions]
      }
    end

    def resolve_missing_folio
      @night_audit = current_hotel.night_audits.find(params[:id])
      booking = current_hotel.bookings.find(params[:booking_id])

      result = ::NightAudits::ResolveMissingFolio.call(
        night_audit: @night_audit,
        booking: booking,
        actor: current_user,
        reason: params[:reason]
      )

      if result.success?
        redirect_to resolve_hotel_night_audit_path(current_hotel, @night_audit), notice: result.message
      else
        redirect_to resolve_hotel_night_audit_path(current_hotel, @night_audit), alert: result.message
      end
    end

    def resolve_missing_nightly_charges
      @night_audit = current_hotel.night_audits.find(params[:id])
      booking = current_hotel.bookings.find(params[:booking_id])

      result = ::NightAudits::ResolveMissingNightlyCharges.call(
        night_audit: @night_audit,
        booking: booking,
        actor: current_user,
        reason: params[:reason]
      )

      if result.success?
        redirect_to resolve_hotel_night_audit_path(current_hotel, @night_audit), notice: result.message
      else
        redirect_to resolve_hotel_night_audit_path(current_hotel, @night_audit), alert: result.message
      end
    end

    def repair_completed_nightly_charges
      @night_audit = current_hotel.night_audits.find(params[:id])
      booking = current_hotel.bookings.find(params.dig(:repair, :booking_id))

      result = ::NightAudits::RepairCompletedNightlyCharges.call(
        night_audit: @night_audit,
        booking: booking,
        actor: current_user,
        reason: params.dig(:repair, :reason)
      )

      redirect_to hotel_night_audit_path(current_hotel, @night_audit, tab: "advanced-actions"),
        (result.success? ? { notice: result.message } : { alert: result.message })
    end

    def create
      business_date = requested_business_date
      force_roll = ActiveModel::Type::Boolean.new.cast(params.dig(:night_audit, :force_roll)) || false
      current_record = current_hotel.current_business_date_record ||
        HotelBusinessDate.initialize_for_hotel!(hotel: current_hotel, date: business_date)

      if current_record.business_date != business_date
        redirect_to hotel_night_audits_path(current_hotel),
          alert: "Business date #{business_date} is not the current accounting business date #{current_record.business_date}."
        return
      end

      if force_roll && !current_user.has_permission?("override_financial_date_lock", hotel: current_hotel)
        redirect_to hotel_night_audits_path(current_hotel), alert: "You do not have permission to force-roll the night audit."
        return
      end

      if force_roll && params.dig(:night_audit, :notes).to_s.strip.blank?
        redirect_to hotel_night_audits_path(current_hotel), alert: "A reason is required to force-roll the night audit."
        return
      end

      unless allow_unclosable_date? || current_hotel.can_audit_date?(business_date) || params.dig(:night_audit, :notes).to_s.strip.present?
        redirect_to hotel_night_audits_path(current_hotel), alert: unclosable_date_message(business_date)
        return
      end

      night_audit = current_hotel.night_audits.find_or_initialize_by(business_date: business_date)
      if night_audit.completed? && !force_roll
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
        force_closed: force_roll
      )

      if night_audit.save
        ::NightAudits::RunJob.perform_later(
          night_audit.id,
          current_user.id,
          allow_unclosable_date: allow_unclosable_date?,
          force_roll: force_roll
        )
        redirect_to hotel_night_audit_path(current_hotel, night_audit), notice: "Night audit has been scheduled in the background. Please wait while it processes."
      else
        redirect_to hotel_night_audits_path(current_hotel), alert: "Night audit could not be created: #{night_audit.errors.full_messages.join(', ')}"
      end
    end

    private

    def selected_tab(labels, default:)
      labels.key?(params[:tab]) ? params[:tab] : default
    end

    def authorize_night_audit_access!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_night_audit", hotel: current_hotel)
    end

    def requested_business_date
      raw_value = params.dig(:night_audit, :business_date)
      raw_value.present? ? Date.parse(raw_value) : authoritative_business_date
    rescue ArgumentError, TypeError
      authoritative_business_date
    end

    def allow_unclosable_date?
      Rails.env.development? && ActiveModel::Type::Boolean.new.cast(params.dig(:night_audit, :allow_unclosable_date))
    end

    def unclosable_date_message(business_date)
      window = current_hotel.business_day_window_for(business_date)
      latest = current_hotel.latest_closable_business_date

      "Business date #{business_date.strftime('%d %b %Y')} cannot be audited yet. The business day ends at #{window.end.strftime('%d %b %Y, %I:%M %p')}. Latest closable date is #{latest.strftime('%d %b %Y')}."
    end

    def authoritative_business_date
      current_hotel.current_business_date ||
        HotelBusinessDate.initialize_for_hotel!(hotel: current_hotel, date: current_hotel.business_date_for(Time.current)).business_date
    end
  end
end
