# frozen_string_literal: true

module HotelPortal
  class RatePlanAttachmentForm
    include ActiveModel::Model

    attr_accessor :rate_plan_id, :rate_plan_name, :room_type_ids
  end
end
