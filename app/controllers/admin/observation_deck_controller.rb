module Admin
  class ObservationDeckController < Admin::BaseController
    AI_PROVIDER_OPTIONS = {
      "gemini" => { label: "Gemini", key: "gemini_api_key" },
      "openai" => { label: "OpenAI", key: "openai_api_key" },
      "deepseek" => { label: "DeepSeek", key: "deepseek_api_key" },
      "claude" => { label: "Claude", key: "anthropic_api_key" }
    }.freeze

    layout "observation_deck"
    before_action :authenticate_superadmin!

    def index
      # Last 24h Pulse Metrics
      last_24h = ObservationEntry.where("created_at > ?", 24.hours.ago)
      @total_requests_24h = last_24h.where(entry_type: "request").count
      @error_count_24h = last_24h.where("status >= 400").count
      @error_rate_24h = @total_requests_24h > 0 ? (@error_count_24h.to_f / @total_requests_24h * 100).round(1) : 0
      @avg_latency_24h = last_24h.where(entry_type: "request").average(:duration).to_f.round(1)

      # Optimization: Do not select the large payload column in index
      # Prioritize errors (status >= 400) first, then chronological
      @entries = ObservationEntry.select(:id, :entry_type, :request_id, :status, :duration, :path, :tags, :created_at)
                                .order(created_at: :desc)

      last_ack = AppConfig.get("observation_deck_last_acknowledged_at")
      @error_count = ObservationEntry.where("status >= 400")
                                    .where("created_at > ?", 24.hours.ago)
      @error_count = @error_count.where("created_at > ?", last_ack) if last_ack.present?
      @error_count = @error_count.count

      if params[:entry_type].present?
        @entries = @entries.where(entry_type: params[:entry_type])
      elsif params[:focus_mode] == "true"
        @entries = @entries.where(entry_type: [ "request", "job", "mail" ])
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
      load_ai_provider_config

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @entry = ObservationEntry.find(params[:id])

      # For traceability, find sibling entries
      if @entry.request_id.present? && @entry.request_id != "none"
        @parent_request = ObservationEntry.find_by(request_id: @entry.request_id, entry_type: "request")

        # Siblings include the current one for highlighting logic in view
        @siblings = ObservationEntry.where(request_id: @entry.request_id)
                                   .select(:id, :entry_type, :path, :duration, :status)
                                   .order(created_at: :asc)
      end

      render layout: false
    end

    def clear
      if params[:keep_days].present?
        days = params[:keep_days].to_i
        ObservationEntry.where("created_at < ?", days.days.ago).delete_all
        notice = "Cleaned up logs older than #{days} days."
      else
        ObservationEntry.delete_all
        notice = "Observation deck cleared."
      end

      redirect_to admin_observation_deck_index_path, notice: notice
    end

    def analyze
      @entry = ObservationEntry.find(params[:id])

      # Use existing analysis unless 'force' is passed
      if @entry.ai_analysis.present? && params[:force] != "true"
        @analysis = @entry.ai_analysis.with_indifferent_access
      else
        @analysis = PlatformControl::AiAnalyzerService.new(@entry).analyze

        # Persist successful analysis
        if @analysis[:html].present?
          @entry.update!(ai_analysis: @analysis)
        end
      end

      respond_to do |format|
        format.turbo_stream
      end
    end

    def acknowledge
      AppConfig.set("observation_deck_last_acknowledged_at", Time.current)
      redirect_to admin_observation_deck_index_path, notice: "All recent errors acknowledged."
    end

    def update_config
      configured_providers = configured_ai_provider_values
      provider = params[:observation_deck_ai_provider].to_s

      if configured_providers.include?(provider)
        AppConfig.set("observation_deck_ai_provider", provider)
        notice = "AI provider updated successfully."
      else
        notice = "Select a configured AI provider first."
      end

      redirect_to admin_observation_deck_index_path, notice: notice
    end

    private

    def load_ai_provider_config
      @configured_ai_providers = configured_ai_provider_options
      selected_provider = AppConfig.get("observation_deck_ai_provider")
      @observation_deck_ai_provider =
        if @configured_ai_providers.any? { |(_label, value)| value == selected_provider }
          selected_provider
        else
          @configured_ai_providers.first&.last
        end
    end

    def configured_ai_provider_options
      AI_PROVIDER_OPTIONS.filter_map do |value, config|
        [ config[:label], value ] if AppConfig.get(config[:key]).present?
      end
    end

    def configured_ai_provider_values
      configured_ai_provider_options.map(&:last)
    end
  end
end
