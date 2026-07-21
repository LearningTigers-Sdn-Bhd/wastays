class FixBookingBillingPartiesAccountTypeAllowAirline < ActiveRecord::Migration[8.0]
  def up
    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_account_type_allowed"
    add_check_constraint :booking_billing_parties,
      "account_type IS NULL OR (account_type::text = ANY (ARRAY['company', 'government', 'travel_agent', 'airline']::text[]))",
      name: "booking_billing_parties_account_type_allowed"
  end

  def down
    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_account_type_allowed"
    add_check_constraint :booking_billing_parties,
      "account_type IS NULL OR (account_type::text = ANY (ARRAY['company', 'government', 'travel_agent']::text[]))",
      name: "booking_billing_parties_account_type_allowed"
  end
end
