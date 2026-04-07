FactoryBot.define do
  factory :pre_checkin do
    booking { nil }
    status { "pending" }
    token { SecureRandom.hex(20) }
    completed_at { nil }
    document_status { "pending" }
    signature_status { "pending" }
    metadata { {} }
  end
end
