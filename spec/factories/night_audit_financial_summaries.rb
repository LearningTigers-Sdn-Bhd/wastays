FactoryBot.define do
  factory :night_audit_financial_summary do
    association :night_audit
    room_revenue { "0.0" }
    tax_revenue { "0.0" }
    payments_total { "0.0" }
    refunds_total { "0.0" }
    no_show_charges { "0.0" }
    changelog { [] }
  end
end
