module PlanFeaturesHelper
  def feature_enabled_for_hotel?(slug, hotel = current_hotel)
    return true if current_user&.superadmin?
    hotel&.feature_enabled?(slug) || false
  end
end
