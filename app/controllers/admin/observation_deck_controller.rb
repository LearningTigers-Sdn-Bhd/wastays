module Admin
  class ObservationDeckController < Admin::BaseController
    layout "observation_deck"
    before_action :authenticate_superadmin!

    def index
      # Last 24h Pulse Metrics
      last_24h = ObservationEntry.where("created_at > ?", 24.hours.ago)
      @total_requests_24h = last_24h.where(entry_type: 'request').count
      @error_count_24h = last_24h.where("status >= 400").count
      @error_rate_24h = @total_requests_24h > 0 ? (@error_count_24h.to_f / @total_requests_24h * 100).round(1) : 0
      @avg_latency_24h = last_24h.where(entry_type: 'request').average(:duration).to_f.round(1)

      # Optimization: Do not select the large payload column in index
      # Prioritize errors (status >= 400) first, then chronological
      @entries = ObservationEntry.select(:id, :entry_type, :request_id, :status, :duration, :path, :tags, :created_at)
                                .order(created_at: :desc)

      @error_count = ObservationEntry.where("status >= 400").where("created_at > ?", 24.hours.ago).count

      if params[:entry_type].present?
        @entries = @entries.where(entry_type: params[:entry_type])
      end

      effective_status_group = params[:status_group].presence

      if effective_status_group == "error"
        @entries = @entries.where("status >= 400")
      elsif params[:status].present?
        @entries = @entries.where(status: params[:status])
      end
      @effective_status_group = effective_status_group

      if params[:query].present?
        # Search in tags or path
        @entries = @entries.where("path ILIKE :q OR tags::text ILIKE :q", q: "%#{params[:query]}%")
      end

      if params[:request_id].present?
        @entries = @entries.where(request_id: params[:request_id])
      end

      @entries = @entries.page(params[:page]).per(50)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @entry = ObservationEntry.find(params[:id])

      # For traceability, find sibling entries
      if @entry.request_id.present? && @entry.request_id != "none"
        @parent_request = ObservationEntry.find_by(request_id: @entry.request_id, entry_type: 'request')
        
        # Siblings include the current one for highlighting logic in view
        @siblings = ObservationEntry.where(request_id: @entry.request_id)
                                   .select(:id, :entry_type, :path, :duration, :status)
                                   .order(created_at: :asc)
      end

      render layout: false
    end

    def clear
      ObservationEntry.delete_all
      redirect_to admin_observation_deck_index_path, notice: "Observation deck cleared."
    end

    def test_email
      SystemMailer.observability_test(current_user.email).deliver_now
      redirect_to admin_observation_deck_index_path, notice: "Test email sent. Check 'mail' filter."
    end

    def analyze
      @entry = ObservationEntry.find(params[:id])
      @analysis = PlatformControl::AiAnalyzerService.new(@entry).analyze

      respond_to do |format|
        format.turbo_stream
      end
    end
  end
end
