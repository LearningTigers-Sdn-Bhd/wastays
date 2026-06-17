# frozen_string_literal: true

module HotelPortal
  class TransactionCodesController < HotelPortal::BaseController
    TABS = %w[default_codes additional_service_codes].freeze

    before_action :set_hotel
    before_action :authorize!
    before_action :set_transaction_code, only: %i[edit update]

    def show
      Financials::EnsureDefaultTransactionCodes.call(@hotel)
      @presenter = transaction_codes_presenter
      append_transaction_codes_tab_breadcrumb
    end

    def new
      @transaction_code = @hotel.transaction_codes.build(kind: "charge", category: "other", active: true)
      @taxes = taxes
    end

    def create
      @transaction_code = @hotel.transaction_codes.build(transaction_code_params.except(:hotel_tax_ids))
      @transaction_code.system_key = unique_system_key(@transaction_code.code)
      @transaction_code.system_required = false

      if @transaction_code.save
        assign_tax_rules(@transaction_code)
        redirect_to hotel_transaction_codes_path(@hotel, tab: "additional_service_codes"), notice: "Transaction code created."
      else
        @taxes = taxes
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @taxes = taxes
    end

    def update
      @transaction_code.assign_attributes(transaction_code_params.except(:hotel_tax_ids))

      if @transaction_code.save
        assign_tax_rules(@transaction_code)
        redirect_to hotel_transaction_codes_path(@hotel, tab: tab_for(@transaction_code)), notice: "Transaction code updated."
      else
        @taxes = taxes
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def transaction_codes_presenter(tab: active_tab)
      HotelPortal::TransactionCodesPresenter.new(
        hotel: @hotel,
        active_tab: tab,
        current_user: current_user
      )
    end

    def set_transaction_code
      @transaction_code = @hotel.transaction_codes.find(params[:id])
    end

    def taxes
      @taxes ||= @hotel.hotel_taxes.order(:enabled, :name)
    end

    def transaction_code_params
      permitted = params.require(:transaction_code).permit(
        :code,
        :name,
        :kind,
        :category,
        :active,
        :gl_account_code,
        :is_taxable,
        hotel_tax_ids: []
      )
      permitted[:code] = normalize_code(permitted[:code]) if permitted.key?(:code)
      permitted[:gl_account_code] = permitted[:gl_account_code].to_s.strip.presence if permitted.key?(:gl_account_code)
      permitted
    end

    def assign_tax_rules(transaction_code)
      tax_ids = Array(transaction_code_params[:hotel_tax_ids]).reject(&:blank?)
      transaction_code.tax_ids = @hotel.hotel_taxes.where(id: tax_ids).pluck(:id)
    end

    def unique_system_key(code)
      base = "custom_#{code.to_s.parameterize(separator: "_").presence || "code"}"
      candidate = base
      suffix = 2

      while @hotel.transaction_codes.exists?(system_key: candidate)
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end

      candidate
    end

    def normalize_code(value)
      value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    end

    def tab_for(transaction_code)
      transaction_code.system_required? || transaction_code.kind == "tax" ? "default_codes" : "additional_service_codes"
    end

    def active_tab
      requested_tab = params[:tab].to_s
      return requested_tab if TABS.include?(requested_tab)

      "default_codes"
    end

    def append_transaction_codes_tab_breadcrumb
      append_breadcrumb({ label: tab_label(@presenter.active_tab), tab_label: true })
    end

    def tab_label(tab)
      @presenter.tabs.find { |item| item[:name] == tab }&.fetch(:label) || "Default Codes"
    end
  end
end
