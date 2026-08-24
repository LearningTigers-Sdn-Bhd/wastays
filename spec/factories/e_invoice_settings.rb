FactoryBot.define do
  factory :e_invoice_setting do
    # TIN and BRN are the hotel's own identity, not the setting's - the setting
    # reads them through from the hotel record.
    association :hotel, tin: "C1234567890", ssm_number: "202301012345"
    enabled { true }
    intermediary_enabled { false }
    # The hotel files under its own LHDN registration, so a usable setting
    # carries its credentials.
    api_environment { "mock" }
    client_id { "hotel-client-id" }
    client_secret { "hotel-client-secret" }
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

    # A hotel that turned the feature on but has not handed over LHDN access.
    trait :not_connected do
      client_id { nil }
      client_secret { nil }
    end
  end
end
