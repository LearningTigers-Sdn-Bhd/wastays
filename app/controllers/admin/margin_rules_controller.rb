class Admin::MarginRulesController < Admin::BaseController
  def index
    prepare_view_data
  end

  def create
    @new_rule = MarginRule.new(margin_rule_params)
    @new_rule.status = "active"

    if @new_rule.save
      redirect_to admin_margin_rules_path, notice: "Margin rule created successfully."
    else
      prepare_view_data
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @rule = MarginRule.find(params[:id])
    @rule.destroy
    redirect_to admin_margin_rules_path, notice: "Margin rule deleted."
  end

  private

  def prepare_view_data
    @all_margin_rules = MarginRule.includes(:settable).order(created_at: :desc)
    @margin_rules = @all_margin_rules.page(params[:page]).per(25)
    @new_rule ||= MarginRule.new
    @hotels = Hotel.order(:name)
    @room_types = RoomType.includes(:hotel).order(:name)
  end

  def margin_rule_params
    params.require(:margin_rule).permit(:rate, :settable_type, :settable_id)
  end
end
