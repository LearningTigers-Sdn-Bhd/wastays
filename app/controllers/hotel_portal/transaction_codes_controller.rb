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
      @tax_rules = tax_rules
    end

    def create
      @transaction_code = @hotel.transaction_codes.build(transaction_code_attributes)
      @transaction_code.system_key = unique_system_key(@transaction_code.code)
      @transaction_code.system_required = false
      normalize_taxable_flag(@transaction_code)

      if @transaction_code.save
        assign_tax_rules(@transaction_code)
        redirect_to hotel_transaction_codes_path(@hotel, tab: "additional_service_codes"), notice: "Transaction code created."
      else
        @tax_rules = tax_rules
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @tax_rules = tax_rules
    end

    def update
      @transaction_code.assign_attributes(transaction_code_attributes)
      normalize_taxable_flag(@transaction_code)

      if @transaction_code.save
        assign_tax_rules(@transaction_code)
        redirect_to hotel_transaction_codes_path(@hotel, tab: tab_for(@transaction_code)), notice: "Transaction code updated."
      else
        @tax_rules = tax_rules
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

    def tax_rules
      @tax_rules ||= primary_tax_rules + custom_tax_rules
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
        hotel_tax_ids: [],
        tax_rule_keys: []
      )
      permitted[:code] = normalize_code(permitted[:code]) if permitted.key?(:code)
      permitted[:gl_account_code] = permitted[:gl_account_code].to_s.strip.presence if permitted.key?(:gl_account_code)
      permitted
    end

    def transaction_code_attributes
      transaction_code_params.except(:hotel_tax_ids, :tax_rule_keys)
    end

    def assign_tax_rules(transaction_code)
      if transaction_code.kind == "tax" || transaction_code.category == "tax"
        transaction_code.transaction_code_taxes.destroy_all
        return
      end

      keys = tax_rule_keys_param
      custom_tax_ids = keys.filter_map { |key| key.delete_prefix("hotel_tax:") if key.start_with?("hotel_tax:") }
      primary_tax_keys = keys.filter_map { |key| key.delete_prefix("primary:") if key.start_with?("primary:") }

      transaction_code.transaction_code_taxes.destroy_all
      @hotel.hotel_taxes.where(id: custom_tax_ids).find_each do |tax|
        transaction_code.transaction_code_taxes.create!(hotel_tax: tax)
      end
      (primary_tax_keys & TransactionCodeTax::PRIMARY_TAX_KEYS).each do |primary_tax_key|
        transaction_code.transaction_code_taxes.create!(primary_tax_key: primary_tax_key)
      end
    end

    def tax_rule_keys_param
      keys = Array(transaction_code_params[:tax_rule_keys]).reject(&:blank?)
      return keys if keys.any?

      Array(transaction_code_params[:hotel_tax_ids]).reject(&:blank?).map { |id| "hotel_tax:#{id}" }
    end

    def normalize_taxable_flag(transaction_code)
      transaction_code.is_taxable = false if transaction_code.kind == "tax" || transaction_code.category == "tax"
    end

    def primary_tax_rules
      [
        {
          key: "primary:sst_tax",
          name: "SST 8%",
          rate_type: "percentage",
          amount: 8.to_d,
          enabled: @hotel.sst_enabled?,
          group: "Primary Taxes"
        },
        {
          key: "primary:tourism_tax",
          name: "Tourism Tax",
          rate_type: "flat",
          amount: @hotel.tourism_tax_amount.to_d,
          enabled: @hotel.tourism_tax_enabled?,
          group: "Primary Taxes"
        }
      ]
    end

    def custom_tax_rules
      @hotel.hotel_taxes.order(:enabled, :name).map do |tax|
        {
          key: "hotel_tax:#{tax.id}",
          name: tax.name,
          rate_type: tax.rate_type,
          amount: tax.amount.to_d,
          enabled: tax.enabled?,
          group: "Additional Taxes & Fees"
        }
      end
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
