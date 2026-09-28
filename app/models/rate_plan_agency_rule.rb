# frozen_string_literal: true

# One agency named by a rate plan's TA access rule -- excluded from it when the
# plan is "all except", or admitted to it when the plan is "only these".
class RatePlanAgencyRule < ApplicationRecord
  belongs_to :rate_plan
  belongs_to :hotel_corporate_account

  validates :hotel_corporate_account_id, uniqueness: { scope: :rate_plan_id }
  validate :same_hotel

  private

  def same_hotel
    return if rate_plan.blank? || hotel_corporate_account.blank?
    return if rate_plan.hotel_id == hotel_corporate_account.hotel_id

    errors.add(:hotel_corporate_account, "must belong to this property")
  end
end
