FactoryBot.define do
  factory :notification_config do
    hotel
    notification_type { "check_in_confirmation" }
    enabled { true }
    channels { %w[whatsapp] }
    settings { {} }
  end
end
