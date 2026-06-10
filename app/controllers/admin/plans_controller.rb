# frozen_string_literal: true

module Admin
  class PlansController < BaseController
    EXTERNAL_AIC_SLUGS = %w[
      whatsapp_automation_flows
      llm_hotels_resorts_homestays
      guest_engagement_flow
      ai_concierge_flow
      activity_offers_flow
      housekeeping_flow
      complaint_system_flow
    ].freeze

    def index
      @plans = Plan.ordered
      @feature_groups = FeatureGroup.ordered.includes(:features)
      @plan_features = PlanFeature.all.index_by { |pf| [ pf.plan_id, pf.feature_id ] }
    end

    def update_matrix
      cells = params.fetch(:cells, {}).values
      external_feature_ids = Feature.where(slug: EXTERNAL_AIC_SLUGS).pluck(:id).to_set
      PlanFeature.transaction do
        cells.each do |c|
          next if external_feature_ids.include?(c[:feature_id].to_i)

          pf = PlanFeature.find_or_initialize_by(plan_id: c[:plan_id], feature_id: c[:feature_id])
          pf.enabled = ActiveModel::Type::Boolean.new.cast(c[:enabled])
          pf.level   = c[:level].presence
          pf.addon   = ActiveModel::Type::Boolean.new.cast(c[:addon])
          pf.save!
        end
      end
      redirect_to admin_plans_path, notice: "Plan matrix updated."
    end
  end
end
