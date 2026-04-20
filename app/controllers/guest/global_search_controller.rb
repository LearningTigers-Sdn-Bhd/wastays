class Guest::GlobalSearchController < Guest::BaseController
  before_action :authenticate_guest!

  def index
    query = params[:q].to_s.strip.downcase
    search_service = Guest::GlobalSearchService.new(current_guest, query)

    results = Rails.cache.fetch(cache_key_for(query), expires_in: 2.minutes) do
      search_service.perform
    end

    render json: {
      results: results,
      quick_actions: search_service.quick_actions
    }
  end

  private

  def cache_key_for(query)
    "guest:global_search:v1:guest:#{current_guest.id}:q:#{Digest::SHA256.hexdigest(query)}"
  end
end
