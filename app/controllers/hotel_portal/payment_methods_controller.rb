# frozen_string_literal: true

module HotelPortal
  class PaymentMethodsController < SettingsBaseController
    include SheetActionCompletion

    before_action :authorize!
    before_action :ensure_defaults, only: :index
    before_action :set_payment_method, only: %i[edit update update_status]
    before_action :prepare_extra_charges, only: %i[new create edit update]

    def index
      @payment_methods = current_hotel.hotel_payment_methods.includes(:transaction_code, surcharge_extra_charge: :transaction_code)
      if params[:q].present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        @payment_methods = @payment_methods.joins(:transaction_code)
          .where("transaction_codes.name ILIKE :term OR transaction_codes.code ILIKE :term", term: term)
      end
      @payment_methods = @payment_methods.ordered
    end

    def new
      @payment_method = build_payment_method
      render layout: false
    end

    def create
      @payment_method = build_payment_method
      save_payment_method("Payment method added.", :new)
    end

    def edit
      render layout: false
    end

    def update
      save_payment_method("Payment method updated.", :edit)
    end

    def update_status
      active = ActiveModel::Type::Boolean.new.cast(params.require(:active))
      if !active && @payment_method.default_cash?
        redirect_to hotel_payment_methods_path(current_hotel), alert: "Choose another default cash method before deactivating this one."
        return
      end

      @payment_method.transaction_code.update!(active: active)
      redirect_to hotel_payment_methods_path(current_hotel), notice: "Payment method status updated."
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def ensure_defaults
      PaymentMethods::EnsureDefaults.call(current_hotel)
    end

    def set_payment_method
      @payment_method = current_hotel.hotel_payment_methods.includes(:transaction_code).find(params[:id])
    end

    def build_payment_method
      transaction_code = current_hotel.transaction_codes.build(
        kind: "payment",
        category: "gateway_payment",
        active: true,
        system_required: false
      )
      current_hotel.hotel_payment_methods.build(
        transaction_code: transaction_code,
        payment_method_type: "bank_gateway",
        position: current_hotel.hotel_payment_methods.maximum(:position).to_i + 1
      )
    end

    def save_payment_method(notice, template)
      result = PaymentMethods::Save.call(payment_method: @payment_method, attributes: payment_method_params)
      if result.success?
        complete_sheet_action(
          destination: hotel_payment_methods_path(current_hotel),
          notice: notice,
          frame: turbo_frame_request_id.presence || "settings_action_sheet"
        )
      else
        render template, formats: :html, layout: false, status: :unprocessable_entity
      end
    end

    def payment_method_params
      params.require(:hotel_payment_method).permit(
        :name, :code, :payment_method_type, :default_cash, :guest_advance, :active,
        :surcharge_enabled, :surcharge_posting_type, :surcharge_value, :surcharge_extra_charge_id
      )
    end

    def prepare_extra_charges
      @surcharge_extra_charges = current_hotel.hotel_extra_charges.active.includes(:transaction_code).ordered
    end
  end
end
