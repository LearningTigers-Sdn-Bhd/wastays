FactoryBot.define do
  factory :refund_policy do
    min_days_before_checkin { 3 }
    refund_percentage { 80.0 }
  end
end
