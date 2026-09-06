class Admin::SetupFeeRulesController < Admin::BaseController
  def index
    load_index_dependencies
  end

  def create
    @new_rule = SetupFeeRule.new(setup_fee_rule_params)
    @new_rule.status = "active"
    @new_rule.currency = SetupFeeRule::CURRENCY if @new_rule.currency.blank?

    if @new_rule.save
      redirect_to admin_setup_fee_rules_path, notice: "Setup fee rule created successfully."
    else
      load_index_dependencies
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @rule = SetupFeeRule.find(params[:id])
    @rule.destroy

    redirect_to admin_setup_fee_rules_path, notice: "Setup fee rule deleted."
  end

  private

  def load_index_dependencies
    @all_setup_fee_rules = SetupFeeRule.includes(:settable).order(created_at: :desc, id: :desc)
    @pagy, @setup_fee_rules = pagy_offset(@all_setup_fee_rules, limit: 25)
    @new_rule ||= SetupFeeRule.new(currency: SetupFeeRule::CURRENCY)
    @hotels = Hotel.order(:name)
  end

  def setup_fee_rule_params
    params.require(:setup_fee_rule).permit(:amount, :currency, :settable_type, :settable_id)
  end
end
