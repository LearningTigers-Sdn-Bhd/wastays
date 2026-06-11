# frozen_string_literal: true

module PlanGated
  extend ActiveSupport::Concern

  private

  def require_feature!(slug)
    return true if current_user&.superadmin?
    return true if current_hotel&.feature_enabled?(slug)

    redirect_to(request.referrer || root_path,
                alert: "This feature isn't included in your plan. Upgrade to access it.")
    false
  end
end
