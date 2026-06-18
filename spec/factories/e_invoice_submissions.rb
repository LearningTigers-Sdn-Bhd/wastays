FactoryBot.define do
  factory :e_invoice_submission do
    association :hotel
    association :booking
    document_type { "01" }
    internal_id { "INV-123" }
    status { "pending" }
  end
end
