# frozen_string_literal: true

module HotelPortal
  # A read-only accounting view of every posting code the hotel has.
  #
  # Codes are no longer created or edited here: each one is owned by the registry
  # that knows what it means (Extra Charges, Discounts, Payment Methods, Taxes &
  # Fees, Room Revenue), and a code invented outside those registries was never
  # postable — the folio charge form reads hotel_extra_charges, not transaction
  # codes. What is left is the ledger view, which accounting still needs.
  class TransactionCodeReferencesController < SettingsBaseController
    before_action :authorize!

    def index
      Financials::EnsureDefaultExtraCharges.call(current_hotel)
      Discounts::EnsureDefaults.call(current_hotel)
      ReservationPolicies::EnsureDefaults.call(current_hotel)

      @transaction_codes = current_hotel.transaction_codes.order(:kind, :code)
      @owners = registry_owners
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    # transaction_code_id => { label:, path:, turbo_frame: } for the registry that owns it.
    def registry_owners
      owners = {}
      current_hotel.hotel_extra_charges.each do |charge|
        owners[charge.transaction_code_id] = { label: "Extra Charges", path: edit_hotel_extra_charge_path(current_hotel, charge), turbo_frame: "settings_action_sheet" }
      end
      current_hotel.hotel_discounts.each do |discount|
        owners[discount.transaction_code_id] = { label: "Discounts", path: edit_hotel_discount_path(current_hotel, discount), turbo_frame: "settings_action_sheet" }
      end
      current_hotel.hotel_payment_methods.each do |method|
        owners[method.transaction_code_id] = { label: "Payment Methods", path: edit_hotel_payment_method_path(current_hotel, method), turbo_frame: "settings_action_sheet" }
      end
      current_hotel.hotel_taxes.where.not(transaction_code_id: nil).each do |tax|
        owners[tax.transaction_code_id] = { label: "Taxes & Fees", path: hotel_taxes_fees_path(current_hotel) }
      end
      current_hotel.hotel_reservation_policies.each do |policy|
        owners[policy.transaction_code_id] = { label: "Room Revenue", path: hotel_room_revenue_path(current_hotel, tab: "reservation_policies") }
      end
      room_revenue = ::TransactionCodes::Resolver.for(current_hotel).room_revenue
      owners[room_revenue.id] = { label: "Room Revenue", path: hotel_room_revenue_path(current_hotel) } if room_revenue
      owners
    end
  end
end
