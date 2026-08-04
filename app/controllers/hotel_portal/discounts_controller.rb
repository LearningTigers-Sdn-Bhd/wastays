# frozen_string_literal: true

module HotelPortal
  class DiscountsController < SettingsBaseController
    include SheetActionCompletion

    before_action :authorize!
    before_action :ensure_defaults, only: :index
    before_action :set_discount, only: %i[edit update update_status]
    before_action :prepare_charge_codes, only: %i[new create edit update]

    def index
      @discounts = current_hotel.hotel_discounts
        .includes(:transaction_code, :applicable_transaction_codes).ordered
    end

    def new
      @discount = build_discount
      render layout: false
    end

    def create
      @discount = build_discount
      save_discount("Discount added.", :new)
    end

    def edit
      render layout: false
    end

    def update
      save_discount("Discount updated.", :edit)
    end

    def update_status
      @discount.transaction_code.update!(active: ActiveModel::Type::Boolean.new.cast(params.require(:active)))
      redirect_to hotel_discounts_path(current_hotel), notice: "Discount status updated."
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def ensure_defaults
      Discounts::EnsureDefaults.call(current_hotel)
    end

    def set_discount
      @discount = current_hotel.hotel_discounts.includes(:transaction_code, :applicable_transaction_codes).find(params[:id])
    end

    def build_discount
      code = current_hotel.transaction_codes.build(kind: "adjustment", category: "discount", active: true, system_required: false)
      current_hotel.hotel_discounts.build(
        transaction_code: code, pricing_type: "manual", application_scope: "all_eligible_charges",
        allow_amount_override: true, position: current_hotel.hotel_discounts.maximum(:position).to_i + 1
      )
    end

    def save_discount(notice, template)
      result = Discounts::Save.call(discount: @discount, attributes: discount_params)
      if result.success?
        complete_sheet_action(destination: hotel_discounts_path(current_hotel), notice:, frame: turbo_frame_request_id.presence || "settings_action_sheet")
      else
        render template, formats: :html, layout: false, status: :unprocessable_entity
      end
    end

    def discount_params
      params.require(:hotel_discount).permit(
        :name, :code, :description, :pricing_type, :rate_value, :application_scope,
        :allow_amount_override, :active, applicable_transaction_code_ids: []
      )
    end

    def prepare_charge_codes
      @charge_codes = current_hotel.transaction_codes.active.where(kind: "charge").where.not(category: "tax").order(:code)
    end
  end
end
