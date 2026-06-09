# frozen_string_literal: true

module HotelPortal
  class PlansController < BaseController
    def show
      @plan = current_hotel.plan
      @feature_groups = FeatureGroup.ordered.includes(:features)
      @enabled_slugs = current_hotel.plan_feature_map.select { |_, v| v[:enabled] }.keys.to_set
      @addon_slugs = current_hotel.plan_feature_map.select { |_, v| v[:addon] }.keys.to_set

      total = Feature.count
      @included_count = @enabled_slugs.size
      @total_count = total
    end
  end
end
