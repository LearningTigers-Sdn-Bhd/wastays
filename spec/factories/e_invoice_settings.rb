FactoryBot.define do
  factory :e_invoice_setting do
    association :hotel
    enabled { true }
    intermediary_enabled { false }
    hotel_tin { "C1234567890" }
    hotel_brn { "202301012345" }
    supplier_msic_code { "55101" }
    supplier_business_description { "Hotel accommodation services" }
    supplier_address_line1 { "1 Jalan Hotel" }
    supplier_address_line2 { "" }
    supplier_city { "Kota Kinabalu" }
    supplier_postal_code { "88000" }
    supplier_state_code { "12" }
    supplier_country_code { "MYS" }
    supplier_contact_phone { "+6088123456" }
    supplier_contact_email { "finance@hotel.test" }

    trait :intermediary_ready do
      intermediary_enabled { true }
    end
  end
end
