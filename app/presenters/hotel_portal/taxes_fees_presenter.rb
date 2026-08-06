# frozen_string_literal: true

module HotelPortal
  class TaxesFeesPresenter
    RegistryRow = Data.define(
      :key,
      :record,
      :system,
      :name,
      :type_label,
      :code,
      :applies_to,
      :charge_rule,
      :charge_amount,
      :enabled,
      :manage_path,
      :status_path,
      :status_param
    )

    TABS = %w[registry malaysia_reference].freeze

    attr_reader :hotel, :current_user, :hotel_tax, :active_tab

    def initialize(hotel:, current_user:, hotel_tax: nil, active_tab: nil)
      @hotel = hotel
      @current_user = current_user
      @hotel_tax = hotel_tax
      @active_tab = TABS.include?(active_tab.to_s) ? active_tab.to_s : "registry"
    end

    def hotel_taxes
      @hotel_taxes ||= hotel.hotel_taxes.includes(:transaction_code).order(:name)
    end

    def registry_rows
      @registry_rows ||= [ sst_row, tourism_tax_row, *hotel_taxes.map { |tax| custom_row(tax) } ]
    end

    def new_hotel_tax
      @new_hotel_tax ||= hotel_tax || hotel.hotel_taxes.build
    end

    private

    def sst_row
      RegistryRow.new(
        key: "sst",
        record: hotel,
        system: true,
        name: "Service Tax (SST)",
        type_label: "Tax",
        code: "TAX_SST",
        applies_to: "All guests",
        charge_rule: "Percentage",
        charge_amount: "8.00%",
        enabled: hotel.sst_enabled?,
        manage_path: routes.hotel_edit_system_tax_path(hotel, "sst"),
        status_path: routes.hotel_system_tax_path(hotel, "sst"),
        status_param: "hotel[sst_enabled]"
      )
    end

    def tourism_tax_row
      RegistryRow.new(
        key: "tourism_tax",
        record: hotel,
        system: true,
        name: "Tourism Tax (TTx)",
        type_label: "Tax",
        code: "TAX_TTX",
        applies_to: "Foreign guests only",
        charge_rule: "Fixed",
        charge_amount: "RM #{formatted_amount(hotel.tourism_tax_amount)} / room / night",
        enabled: hotel.tourism_tax_enabled?,
        manage_path: routes.hotel_edit_system_tax_path(hotel, "tourism_tax"),
        status_path: routes.hotel_system_tax_path(hotel, "tourism_tax"),
        status_param: "hotel[tourism_tax_enabled]"
      )
    end

    def custom_row(tax)
      RegistryRow.new(
        key: "hotel_tax_#{tax.id}",
        record: tax,
        system: false,
        name: tax.name,
        type_label: tax.charge_type == "tax" ? "Tax" : "Fee",
        code: tax.transaction_code&.code.presence || tax.transaction_code_value,
        applies_to: tax.foreign_guests_only? ? "Foreign guests only" : "All guests",
        charge_rule: tax.rate_type == "percentage" ? "Percentage" : "Fixed",
        charge_amount: tax.rate_type == "percentage" ? "#{formatted_amount(tax.amount)}%" : "RM #{formatted_amount(tax.amount)}",
        enabled: tax.enabled?,
        manage_path: routes.edit_hotel_hotel_tax_path(hotel, tax),
        status_path: routes.hotel_hotel_tax_path(hotel, tax),
        status_param: "hotel_tax[enabled]"
      )
    end

    def formatted_amount(amount)
      ActiveSupport::NumberHelper.number_to_rounded(amount.to_d, precision: 2, delimiter: ",", strip_insignificant_zeros: false)
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
