module HotelPortal
  class GlobalSearchController < BaseController
    def index
      query = params[:q].to_s.strip.downcase
      search_service = HotelPortal::GlobalSearchService.new(
        current_hotel, query, user: current_user, layer: requested_layer
      )

      results = Rails.cache.fetch(cache_key_for(query), expires_in: 2.minutes) do
        search_service.perform
      end

      render json: {
        results: results,
        quick_actions: search_service.quick_actions
      }
    end

    private

    # The sidebar key the asking page renders under, mapped back to its layer.
    # Anything unrecognised is treated as operations, the default layer.
    LAYER_BY_NAVIGATION_KEY = {
      "hotel" => :operations,
      "hotel-financials" => :financials,
      "hotel-reports" => :reports,
      "hotel-settings" => :settings
    }.freeze

    def requested_layer
      LAYER_BY_NAVIGATION_KEY.fetch(params[:layer].to_s, :operations)
    end

    def cache_key_for(query)
      "hotel:global_search:v8:hotel:#{current_hotel.id}:user:#{current_user.id}:layer:#{requested_layer}:q:#{Digest::SHA256.hexdigest(query)}"
    end
  end
end
