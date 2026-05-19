# frozen_string_literal: true

class Admin::ExchangeRatesController < Admin::BaseController
  def index
    load_rates
  end

  def create
    @exchange_rate = ExchangeRate.new(exchange_rate_params.merge(created_by: current_user))

    if @exchange_rate.save
      redirect_to admin_exchange_rates_path, notice: "Exchange rate saved."
    else
      load_rates
      render :index, status: :unprocessable_content
    end
  end

  def update
    @exchange_rate = ExchangeRate.find(params[:id])

    if @exchange_rate.update(exchange_rate_params.merge(created_by: current_user))
      redirect_to admin_exchange_rates_path, notice: "Exchange rate updated."
    else
      load_rates
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    ExchangeRate.find(params[:id]).destroy
    redirect_to admin_exchange_rates_path, notice: "Exchange rate removed."
  end

  private

  def load_rates
    @exchange_rates = ExchangeRate.order(:base_currency, :currency_code)
    @exchange_rate ||= ExchangeRate.new(effective_at: Time.current, source: "manual", active: true, base_currency: "MYR")
    @currency_options = CurrencyCatalog.options
  end

  def exchange_rate_params
    params.require(:exchange_rate).permit(:base_currency, :currency_code, :rate, :effective_at, :source, :active)
  end
end
