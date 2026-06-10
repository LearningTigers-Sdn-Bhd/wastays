# frozen_string_literal: true

module Folios
  module ChargePostingKeys
    module_function

    def nightly_charge_key(booking:, date:, charge_kind:, identity:)
      [ booking.id, date.to_date.iso8601, charge_kind, identity ].join(":")
    end

    def catch_up_charge_key(booking:, date:, charge_kind:, identity:)
      [ "catch_up", booking.id, date.to_date.iso8601, charge_kind, identity ].join(":")
    end

    def early_checkout_charge_key(booking:, date:, charge_kind:, identity: nil)
      [ "early_checkout", booking.id, date.to_date.iso8601, charge_kind, identity ].compact.join(":")
    end

    def no_show_charge_key(booking:, date:, charge_kind:, identity:)
      [ booking.id, date.to_date.iso8601, "no_show_charge", charge_kind, identity ].join(":")
    end
  end
end
