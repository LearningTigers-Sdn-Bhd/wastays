# frozen_string_literal: true

module Onboarding
  class SectionCatalog
    Section = Data.define(:key, :phase, :required, :route_name, :prerequisites)

    SECTIONS = [
      Section.new(key: "property_profile", phase: "property", required: true, route_name: "property_profile", prerequisites: []),
      # Photos stand apart from the profile fields: they upload on their own as
      # soon as they are chosen, rather than being saved by the profile form.
      Section.new(key: "property_photos", phase: "property", required: true, route_name: "property_photos", prerequisites: [ "property_profile" ]),
      Section.new(key: "roles_permissions", phase: "team", required: true, route_name: "roles_permissions", prerequisites: [ "property_photos" ]),
      Section.new(key: "staff_setup", phase: "team", required: false, route_name: "staff_setup", prerequisites: [ "roles_permissions" ]),
      Section.new(key: "taxes_fees", phase: "finance", required: true, route_name: "taxes_fees", prerequisites: [ "staff_setup" ]),
      Section.new(key: "room_revenue", phase: "finance", required: true, route_name: "room_revenue", prerequisites: [ "taxes_fees" ]),
      Section.new(key: "rooms", phase: "rooms_rates", required: true, route_name: "rooms", prerequisites: [ "room_revenue" ]),
      Section.new(key: "rates_availability", phase: "rooms_rates", required: true, route_name: "rates_availability", prerequisites: [ "rooms" ]),
      Section.new(key: "extra_charges", phase: "commercial", required: false, route_name: "extra_charges", prerequisites: [ "rates_availability" ]),
      Section.new(key: "discounts", phase: "commercial", required: false, route_name: "discounts", prerequisites: [ "extra_charges" ]),
      Section.new(key: "payment_methods", phase: "commercial", required: true, route_name: "payment_methods", prerequisites: [ "discounts" ]),
      Section.new(key: "corporate_accounts", phase: "commercial", required: false, route_name: "corporate_accounts", prerequisites: [ "payment_methods" ]),
      Section.new(key: "channel_manager", phase: "commercial", required: false, route_name: "channel_manager", prerequisites: [ "corporate_accounts" ]),
      Section.new(key: "review", phase: "review", required: true, route_name: "review", prerequisites: [ "channel_manager" ])
    ].freeze

    class << self
      def all = SECTIONS
      def keys = SECTIONS.map(&:key)
      def fetch(key) = SECTIONS.find { |section| section.key == key.to_s } || raise(KeyError, "Unknown onboarding section: #{key}")

      def order_sql(column)
        quoted = ActiveRecord::Base.connection.quote_column_name(column)
        clauses = keys.each_with_index.map { |key, index| "WHEN #{ActiveRecord::Base.connection.quote(key)} THEN #{index}" }
        "CASE #{quoted} #{clauses.join(' ')} ELSE #{keys.length} END"
      end
    end
  end
end
