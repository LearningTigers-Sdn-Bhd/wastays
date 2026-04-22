module Admin
  class GlobalSearchController < BaseController
    def index
      query = params[:q].to_s.strip.downcase
      search_service = Admin::GlobalSearchService.new(query)

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
      "admin:global_search:v7:user:#{current_user.id}:q:#{Digest::SHA256.hexdigest(query)}"
    end
  end
end
