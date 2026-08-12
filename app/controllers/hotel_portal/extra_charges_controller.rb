# frozen_string_literal: true

module HotelPortal
  class ExtraChargesController < SettingsBaseController
    include SheetActionCompletion

    before_action :authorize!
    before_action :ensure_defaults, only: :index
    before_action :set_extra_charge, only: %i[edit update update_status]
    before_action :prepare_tax_rules, only: %i[new create edit update]

    def index
      @extra_charges = current_hotel.hotel_extra_charges
        .includes(transaction_code: [ :transaction_code_taxes, :taxes ])
        .ordered
    end

    def new
      @extra_charge = build_extra_charge
      render layout: false
    end

    def create
      @extra_charge = build_extra_charge
      save_extra_charge("Extra charge added.", :new)
    end

    def edit
      render layout: false
    end

    def update
      save_extra_charge("Extra charge updated.", :edit)
    end

    def update_status
      @extra_charge.transaction_code.update!(active: ActiveModel::Type::Boolean.new.cast(params.require(:active)))
      redirect_to hotel_extra_charges_path(current_hotel), notice: "Extra charge status updated."
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def ensure_defaults
      Financials::EnsureDefaultExtraCharges.call(current_hotel)
    end

    def set_extra_charge
      @extra_charge = current_hotel.hotel_extra_charges.includes(transaction_code: :transaction_code_taxes).find(params[:id])
    end

    def build_extra_charge
      transaction_code = current_hotel.transaction_codes.build(
        kind: "charge",
        category: "other",
        active: true,
        system_required: false
      )
      current_hotel.hotel_extra_charges.build(
        transaction_code: transaction_code,
        pricing_type: "manual",
        charging_unit: "per_item",
        allow_amount_override: true,
        position: current_hotel.hotel_extra_charges.maximum(:position).to_i + 1
      )
    end

    def save_extra_charge(notice, template)
      result = ExtraCharges::Save.call(
        extra_charge: @extra_charge,
        attributes: extra_charge_params,
        tax_rule_keys: extra_charge_params[:tax_rule_keys]
      )
      if result.success?
        complete_sheet_action(
          destination: hotel_extra_charges_path(current_hotel),
          notice: notice,
          frame: turbo_frame_request_id.presence || "settings_action_sheet"
        )
      else
        render template, formats: :html, layout: false, status: :unprocessable_entity
      end
    end

    def extra_charge_params
      params.require(:hotel_extra_charge).permit(
        :name, :code, :description, :category, :pricing_type, :rate_value,
        :charging_unit, :percentage_basis, :allow_amount_override, :active,
        tax_rule_keys: []
      )
    end

    def prepare_tax_rules
      @tax_rule_choices = TaxRuleOptionsQuery.new(current_hotel).choices
    end
  end
end
