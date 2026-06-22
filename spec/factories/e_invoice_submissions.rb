FactoryBot.define do
  factory :e_invoice_submission do
    association :hotel
    association :booking
    document_scenario { "guest_invoice" }
    document_type { "01" }
    submission_mode { "taxpayer" }
    fund_collector { "wastays" }
    supplier_name { "Jesselton Pixel Sdn Bhd" }
    supplier_tin { "C1234567890" }
    internal_id { "INV-123" }
    status { "pending" }
  end
end
