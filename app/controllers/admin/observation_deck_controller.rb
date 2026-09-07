# frozen_string_literal: true

module Admin
  class ObservationDeckController < Admin::BaseController
    AI_PROVIDER_OPTIONS = {
      "gemini" => { label: "Gemini", key: "gemini_api_key" },
      "openai" => { label: "OpenAI", key: "openai_api_key" },
      "deepseek" => { label: "DeepSeek", key: "deepseek_api_key" },
      "claude" => { label: "Claude", key: "anthropic_api_key" }
    }.freeze
    TIME_RANGES = { "hour" => 1.hour, "day" => 24.hours, "week" => 7.days }.freeze
    ENTRY_TYPES = %w[request sql job mail api].freeze
    STATUS_GROUPS = %w[errors success].freeze

    layout "observation_deck"
    before_action :authenticate_superadmin!
    rescue_from ActiveRecord::RecordNotFound, with: :entry_not_found

    def index
      load_entries
      load_health
      load_ai_provider_config

      respond_to do |format|
        format.html
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("observation-app-bar", partial: "app_bar", formats: [ :html ]),
            turbo_stream.replace("observation-health-strip", partial: "health_strip", formats: [ :html ]),
            turbo_stream.replace("entries_frame", partial: "entries_frame", formats: [ :html ])
          ]
        end
      end
    end

    def show
      @entry = ObservationEntry.find(params[:id])
      @entry_presenter = ObservationDeck::EntryPresenter.new(@entry)
      @trace_entries = trace_entries_for(@entry)
      @trace_presenters = ObservationDeck::EntryPresenter.for(@trace_entries)
      load_ai_provider_config

      render layout: false
    end

    # Existing destructive maintenance endpoint. Automatic seven-day retention
    # remains owned by ObservationDeck::PruneEntries and its scheduled job.
    def clear
      if params[:keep_days].present?
        days = params[:keep_days].to_i
        ObservationEntry.where("created_at < ?", days.days.ago).delete_all
        notice = "Cleaned up logs older than #{days} days."
      else
        ObservationEntry.delete_all
        notice = "Observation deck cleared."
      end

      redirect_to admin_observation_deck_index_path, notice:
    end

    def analyze
      @entry = ObservationEntry.find(params[:id])
      @analysis = if @entry.ai_analysis.present? && params[:force] != "true"
        @entry.ai_analysis.with_indifferent_access
      else
        result = PlatformControl::AiAnalyzerService.new(@entry).analyze
        @entry.update!(ai_analysis: result) if result[:html].present?
        result
      end
      @entry_presenter = ObservationDeck::EntryPresenter.new(@entry)
      load_ai_provider_config

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

      notice = if configured_providers.include?(provider)
        AppConfig.set("observation_deck_ai_provider", provider)
        "AI provider updated successfully."
      else
        "Select a configured AI provider first."
      end

      redirect_to admin_observation_deck_index_path, notice:
    end

    private

    def load_health
      range_key = @filter_params[:time_range] || "day"
      observations = ObservationEntry.where("created_at >= ?", TIME_RANGES.fetch(range_key).ago)
      @health_scope_label = ObservationDeck::FilterBar::TIME_RANGE_OPTIONS.find { |_label, value| value == range_key }.first
      @total_requests = observations.where(entry_type: "request").count
      @health_error_count = observations.where("status >= 400").count
      @health_error_rate = @total_requests.positive? ? (@health_error_count.to_f / @total_requests * 100).round(1) : 0
      @average_latency = observations.where(entry_type: "request").average(:duration).to_f.round(1)

      last_acknowledged_at = AppConfig.get("observation_deck_last_acknowledged_at")
      @error_count = observations.where("status >= 400")
      @error_count = @error_count.where("created_at > ?", last_acknowledged_at) if last_acknowledged_at.present?
      @error_count = @error_count.count
    end

    def load_entries
      @filter_params = normalized_filter_params
      @entries = ObservationEntry.select(:id, :entry_type, :request_id, :status, :duration, :path, :tags, :created_at)
                                 .order(created_at: :desc, id: :desc)
      apply_filters
      @pagy, @entries = pagy(:offset, @entries, limit: 50)
      @entry_presenters = ObservationDeck::EntryPresenter.for(@entries)
    end

    def normalized_filter_params
      {
        query: params[:query].to_s.strip.presence,
        time_range: TIME_RANGES.key?(params[:time_range]) ? params[:time_range] : nil,
        entry_type: (params[:entry_type] if params[:entry_type].in?(ENTRY_TYPES)),
        status_group: (params[:status_group] if params[:status_group].in?(STATUS_GROUPS)),
        request_id: params[:request_id].to_s.strip.presence,
        min_duration: positive_number(params[:min_duration]),
        exact_status: valid_status(params[:exact_status]),
        tags: params[:tags].to_s.strip.presence
      }.compact
    end

    def apply_filters
      @entries = @entries.where("created_at >= ?", TIME_RANGES.fetch(@filter_params[:time_range]).ago) if @filter_params[:time_range]
      @entries = @entries.where(entry_type: @filter_params[:entry_type]) if @filter_params[:entry_type]
      @entries = @entries.where("status >= 400") if @filter_params[:status_group] == "errors"
      @entries = @entries.where("status < 400") if @filter_params[:status_group] == "success"
      @entries = @entries.where("path ILIKE :query OR tags::text ILIKE :query", query: "%#{@filter_params[:query]}%") if @filter_params[:query]
      @entries = @entries.where(request_id: @filter_params[:request_id]) if @filter_params[:request_id]
      @entries = @entries.where("duration >= ?", @filter_params[:min_duration]) if @filter_params[:min_duration]
      @entries = @entries.where(status: @filter_params[:exact_status]) if @filter_params[:exact_status]
      @entries = @entries.where("tags @> ?::jsonb", [ @filter_params[:tags] ].to_json) if @filter_params[:tags]
    end

    def trace_entries_for(entry)
      return [] unless entry.request_id.present? && entry.request_id != "none"

      ObservationEntry.where(request_id: entry.request_id)
                      .select(:id, :entry_type, :request_id, :path, :duration, :status, :tags, :created_at)
                      .order(created_at: :asc)
    end

    def load_ai_provider_config
      @configured_ai_providers = configured_ai_provider_options
      selected_provider = AppConfig.get("observation_deck_ai_provider")
      @observation_deck_ai_provider = if @configured_ai_providers.any? { |(_label, value)| value == selected_provider }
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

    def positive_number(value)
      number = Float(value, exception: false)
      number if number&.positive?
    end

    def valid_status(value)
      number = Integer(value, exception: false)
      number if number&.between?(100, 599)
    end

    def entry_not_found
      render partial: "admin/observation_deck/inspector/not_found", layout: false
    end
  end
end
