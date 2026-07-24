# frozen_string_literal: true

module ObservationDeck
  class FilterBar < ViewComponent::Base
    TIME_RANGE_OPTIONS = [ [ "Last hour", "hour" ], [ "Last 24 hours", "day" ], [ "Last seven days", "week" ] ].freeze
    TYPE_OPTIONS = [ [ "All", "" ], [ "Request", "request" ], [ "SQL", "sql" ], [ "Job", "job" ], [ "Mail", "mail" ], [ "API", "api" ] ].freeze
    STATUS_OPTIONS = [ [ "All", "" ], [ "Errors", "errors" ], [ "Successful", "success" ] ].freeze

    def initialize(params:, clear_path:)
      @params = params
      @clear_path = clear_path
    end

    def active_filters
      {
        "Search: #{@params[:query]}" => :query,
        "Time: #{label_for(TIME_RANGE_OPTIONS, @params[:time_range])}" => :time_range,
        "Type: #{label_for(TYPE_OPTIONS, @params[:entry_type])}" => :entry_type,
        "Status: #{label_for(STATUS_OPTIONS, @params[:status_group])}" => :status_group,
        "Request: #{@params[:request_id]}" => :request_id,
        "Min: #{@params[:min_duration]} ms" => :min_duration,
        "HTTP: #{@params[:exact_status]}" => :exact_status,
        "Tag: #{@params[:tags]}" => :tags
      }.filter { |_label, key| @params[key].present? }
    end

    def form_params
      @params.slice(:query, :time_range, :entry_type, :status_group, :request_id, :min_duration, :exact_status, :tags)
    end

    def quick_filter_path(key, value)
      helpers.admin_observation_deck_index_path(value.present? ? form_params.merge(key => value) : form_params.except(key))
    end

    private

    def label_for(options, value)
      options.find { |_label, option_value| option_value == value }&.first
    end
  end
end
